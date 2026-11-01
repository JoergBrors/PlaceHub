using System.Collections.Concurrent;

namespace PlaceHub.Core;

public interface IAdministrationRepository
{
    IReadOnlyCollection<AdministrationRequest> GetAll();
    AdministrationRequest? Find(Guid id);
    bool TryAdd(AdministrationRequest request);
}

public sealed class InMemoryAdministrationRepository : IAdministrationRepository
{
    private readonly ConcurrentDictionary<Guid, AdministrationRequest> items = new();
    private readonly ConcurrentDictionary<string, Guid> keys = new(StringComparer.Ordinal);
    public IReadOnlyCollection<AdministrationRequest> GetAll() => items.Values.OrderByDescending(x => x.Audit[0].At).ToArray();
    public AdministrationRequest? Find(Guid id) => items.GetValueOrDefault(id);
    public bool TryAdd(AdministrationRequest request)
    {
        if (!keys.TryAdd(request.IdempotencyKey, request.Id)) return false;
        if (items.TryAdd(request.Id, request)) return true;
        keys.TryRemove(request.IdempotencyKey, out _); return false;
    }
}

public sealed record ProvisioningResult(RequestState State, string OutcomeCode);
public interface IProvisioningWorker { Task<ProvisioningResult> ExecuteAsync(AdministrationRequest request, CancellationToken cancellationToken); }

public sealed class OfflineMockProvisioningWorker : IProvisioningWorker
{
    public const bool TenantAccessEnabled = false;
    private static readonly IReadOnlySet<OperationKind> AllowedOperations = new HashSet<OperationKind>(Enum.GetValues<OperationKind>());
    public Task<ProvisioningResult> ExecuteAsync(AdministrationRequest request, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (TenantAccessEnabled) throw new InvalidOperationException("OFFLINE_BOUNDARY_BROKEN");
        if (!AllowedOperations.Contains(request.Specification.Operation)) return Task.FromResult(new ProvisioningResult(RequestState.Failed, "OPERATION_NOT_ALLOWLISTED"));
        var name = request.Specification.Name;
        var result = name.Contains("teilfehler", StringComparison.OrdinalIgnoreCase)
            ? new ProvisioningResult(RequestState.PartiallyConfigured, "MOCK_PARTIAL_CONFIGURATION")
            : name.Contains("abgleich", StringComparison.OrdinalIgnoreCase)
                ? new ProvisioningResult(RequestState.RequiresReconciliation, "MOCK_RECONCILIATION_REQUIRED")
                : new ProvisioningResult(RequestState.Succeeded, "MOCK_VERIFIED");
        return Task.FromResult(result);
    }
}

public sealed class DisabledProvisioningWorker : IProvisioningWorker
{
    public Task<ProvisioningResult> ExecuteAsync(AdministrationRequest request, CancellationToken cancellationToken) =>
        throw new WorkflowException("PRIVILEGED_EXECUTION_NOT_ACTIVATED");
}

public sealed class AdministrationService(IAdministrationRepository repository, IProvisioningWorker worker)
{
    public AdministrationRequest Create(ResourceSpecification specification, Actor actor, string idempotencyKey)
    {
        var request = new AdministrationRequest(specification, actor, idempotencyKey, Guid.NewGuid().ToString("N"));
        if (!repository.TryAdd(request)) throw new WorkflowException("DUPLICATE_REQUEST");
        return request;
    }
    public IReadOnlyCollection<AdministrationRequest> List(Actor actor) => repository.GetAll().Where(x => actor.LocationIds.Contains(x.Specification.LocationId)).ToArray();
    public AdministrationRequest Get(Guid id, Actor actor)
    {
        var request = repository.Find(id) ?? throw new WorkflowException("REQUEST_NOT_FOUND");
        if (!actor.LocationIds.Contains(request.Specification.LocationId)) throw new AuthorizationException("LOCATION_OUT_OF_SCOPE");
        return request;
    }
    public async Task ExecuteAsync(Guid id, Actor actor, int version, CancellationToken cancellationToken = default)
    {
        var request = Get(id, actor); request.Start(actor, version);
        try { var result = await worker.ExecuteAsync(request, cancellationToken); request.Complete(result.State, result.OutcomeCode); }
        catch (OperationCanceledException) { request.Complete(RequestState.RequiresReconciliation, "EXECUTION_CANCELLED_UNVERIFIED"); throw; }
        catch { request.Complete(RequestState.Failed, "MOCK_WORKER_FAILED"); }
    }
}

public sealed record DeskPool(string Id, string LocationId, string Building, string Floor, string Section, string Name, int Capacity, string Status, string MailboxAlias, int RelatedDesks);
public static class SyntheticResources
{
    public static IReadOnlyList<DeskPool> DeskPools { get; } =
    [
        new("workspace-berlin-3-nord", "BER", "Berlin Mitte", "3", "Nord", "Fokus Nord", 18, "Bereit", "workspace-berlin-3-nord", 18),
        new("workspace-berlin-4-sued", "BER", "Berlin Mitte", "4", "Süd", "Projekt Süd", 12, "Ausstehend", "workspace-berlin-4-sued", 12),
        new("workspace-hamburg-2-west", "HAM", "Hamburg Hafen", "2", "West", "Hafen West", 24, "Abgleich erforderlich", "workspace-hamburg-2-west", 24)
    ];
}
