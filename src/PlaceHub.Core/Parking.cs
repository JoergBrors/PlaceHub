using System.Collections.Concurrent;

namespace PlaceHub.Core;

public enum ParkingCategory { Standard, Accessible, ElectricVehicle, Visitor, Reserved }
public enum ParkingStatus { PendingVerification, Provisioning, Active, RequiresReconciliation, Failed, DisabledRequested }

/// <summary>
/// PlaceHub-owned business metadata for a parking space. The Exchange resource mailbox stays authoritative for availability,
/// reservations and mailbox state; nothing here is a second booking engine and nothing implies a Places desk or workspace.
/// </summary>
public sealed record ParkingSpace(
    Guid Id, string LocationId, string MailboxAddress, string DisplayName, ParkingCategory Category, bool Accessible, bool EvCharging,
    ParkingStatus Status, string OutcomeCode, DateTimeOffset? LastVerifiedAt, Guid? LastRequestId);

public interface IParkingRepository
{
    IReadOnlyCollection<ParkingSpace> GetAll();
    ParkingSpace? Find(Guid id);
    bool TryAdd(ParkingSpace space);
    void Replace(ParkingSpace space);
}

/// <summary>Development-only, non-persistent store. Real persistence needs the ADR-010 amendment for non-synthetic data.</summary>
public sealed class InMemoryParkingRepository : IParkingRepository
{
    private readonly ConcurrentDictionary<Guid, ParkingSpace> items = new();
    private readonly ConcurrentDictionary<string, Guid> addresses = new(StringComparer.OrdinalIgnoreCase);
    public IReadOnlyCollection<ParkingSpace> GetAll() => items.Values.OrderBy(x => x.DisplayName, StringComparer.OrdinalIgnoreCase).ToArray();
    public ParkingSpace? Find(Guid id) => items.GetValueOrDefault(id);
    public bool TryAdd(ParkingSpace space)
    {
        if (!addresses.TryAdd(space.MailboxAddress, space.Id)) return false;
        if (items.TryAdd(space.Id, space)) return true;
        addresses.TryRemove(space.MailboxAddress, out _); return false;
    }
    public void Replace(ParkingSpace space) { if (items.ContainsKey(space.Id)) items[space.Id] = space; }
}

public sealed class ParkingService(IParkingRepository repository, AdministrationService administration)
{
    private static void RequireLocation(Actor actor, string locationId) { if (!actor.LocationIds.Contains(locationId)) throw new AuthorizationException("LOCATION_OUT_OF_SCOPE"); }
    private static void ValidateMetadata(string displayName, string mailbox)
    {
        if (string.IsNullOrWhiteSpace(displayName) || displayName.Length > 128) throw new ValidationException("PARKING_DISPLAY_NAME_INVALID");
        if (!ExchangeSpec.IsValidAddress(mailbox)) throw new ValidationException("MAILBOX_ADDRESS_INVALID");
    }

    public IReadOnlyCollection<ParkingSpace> List(Actor actor) { Refresh(); return repository.GetAll().Where(x => actor.LocationIds.Contains(x.LocationId)).ToArray(); }

    public ParkingSpace Get(Guid id, Actor actor)
    {
        Refresh();
        var space = repository.Find(id) ?? throw new WorkflowException("PARKING_NOT_FOUND");
        RequireLocation(actor, space.LocationId); return space;
    }

    /// <summary>Registers an existing resource mailbox. The mailbox is verified by the isolated worker (read-only); until then the space is PendingVerification.</summary>
    public (ParkingSpace Space, AdministrationRequest Request) RegisterExisting(Actor actor, string locationId, string mailboxAddress, string displayName, ParkingCategory category, bool accessible, bool evCharging)
    {
        RequireLocation(actor, locationId); ValidateMetadata(displayName, mailboxAddress);
        var request = administration.Create(ResourceSpecification.ForExchange(OperationKind.Reconcile, locationId, displayName, new ExchangeSpec(mailboxAddress)), actor, Guid.NewGuid().ToString("N"));
        var space = new ParkingSpace(Guid.NewGuid(), locationId, mailboxAddress.ToLowerInvariant(), displayName, category, accessible || category == ParkingCategory.Accessible, evCharging || category == ParkingCategory.ElectricVehicle, ParkingStatus.PendingVerification, "REGISTRATION_SUBMITTED", null, request.Id);
        if (!repository.TryAdd(space)) throw new WorkflowException("PARKING_MAILBOX_ALREADY_REGISTERED");
        request.Submit(actor, request.Version);
        return (space, request);
    }

    /// <summary>Requests creation of a new mailbox. Execution stays blocked until mailbox type, naming, permissions and residual risk are approved.</summary>
    public (ParkingSpace Space, AdministrationRequest Request) RequestCreate(Actor actor, string locationId, ExchangeSpec spec, ParkingCategory category, bool accessible, bool evCharging)
    {
        RequireLocation(actor, locationId); ValidateMetadata(spec.DisplayName ?? "", spec.MailboxAddress);
        var request = administration.Create(ResourceSpecification.ForExchange(OperationKind.Create, locationId, spec.DisplayName!, spec), actor, Guid.NewGuid().ToString("N"));
        var space = new ParkingSpace(Guid.NewGuid(), locationId, spec.MailboxAddress.ToLowerInvariant(), spec.DisplayName!, category, accessible || category == ParkingCategory.Accessible, evCharging || category == ParkingCategory.ElectricVehicle, ParkingStatus.Provisioning, "CREATE_SUBMITTED", null, request.Id);
        if (!repository.TryAdd(space)) throw new WorkflowException("PARKING_MAILBOX_ALREADY_REGISTERED");
        request.Submit(actor, request.Version);
        return (space, request);
    }

    public AdministrationRequest RequestBookingPolicy(Actor actor, Guid spaceId, string policyTemplateId)
    {
        var space = Get(spaceId, actor);
        var request = administration.Create(ResourceSpecification.ForExchange(OperationKind.ChangeBookingPolicy, space.LocationId, space.DisplayName, new ExchangeSpec(space.MailboxAddress, PolicyTemplateId: policyTemplateId)), actor, Guid.NewGuid().ToString("N"));
        request.Submit(actor, request.Version);
        repository.Replace(space with { LastRequestId = request.Id, OutcomeCode = "POLICY_SUBMITTED" });
        return request;
    }

    public AdministrationRequest RequestDisable(Actor actor, Guid spaceId)
    {
        var space = Get(spaceId, actor);
        var request = administration.Create(ResourceSpecification.ForExchange(OperationKind.Disable, space.LocationId, space.DisplayName, new ExchangeSpec(space.MailboxAddress)), actor, Guid.NewGuid().ToString("N"));
        request.Submit(actor, request.Version);
        repository.Replace(space with { Status = ParkingStatus.DisabledRequested, LastRequestId = request.Id, OutcomeCode = "DISABLE_SUBMITTED" });
        return request;
    }

    /// <summary>Edits PlaceHub-owned metadata only; it never changes the Exchange mailbox.</summary>
    public ParkingSpace UpdateMetadata(Actor actor, Guid spaceId, ParkingCategory category, bool accessible, bool evCharging)
    {
        var space = Get(spaceId, actor);
        var updated = space with { Category = category, Accessible = accessible || category == ParkingCategory.Accessible, EvCharging = evCharging || category == ParkingCategory.ElectricVehicle };
        repository.Replace(updated); return updated;
    }

    /// <summary>Maps worker outcomes onto the business status. Exchange remains the source of truth; this only mirrors the verified result.</summary>
    public void Refresh()
    {
        foreach (var space in repository.GetAll())
        {
            if (space.LastRequestId is not { } id) continue;
            var request = administration.FindUnscoped(id);
            if (request is null) continue;
            var status = request.State switch
            {
                RequestState.Succeeded => request.Specification.Operation == OperationKind.Disable ? ParkingStatus.DisabledRequested : ParkingStatus.Active,
                RequestState.PendingPropagation or RequestState.Running or RequestState.Approved or RequestState.AwaitingApproval or RequestState.Submitted or RequestState.Draft => space.Status == ParkingStatus.PendingVerification ? ParkingStatus.PendingVerification : space.Status,
                RequestState.RequiresReconciliation or RequestState.PartiallyConfigured => ParkingStatus.RequiresReconciliation,
                RequestState.Failed or RequestState.Rejected => space.Status == ParkingStatus.Active ? ParkingStatus.Active : ParkingStatus.Failed,
                _ => space.Status
            };
            var verified = request.State == RequestState.Succeeded ? DateTimeOffset.UtcNow : space.LastVerifiedAt;
            if (status != space.Status || request.OutcomeCode != space.OutcomeCode) repository.Replace(space with { Status = status, OutcomeCode = request.OutcomeCode, LastVerifiedAt = verified });
        }
    }
}
