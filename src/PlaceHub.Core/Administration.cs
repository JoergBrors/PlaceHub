using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace PlaceHub.Core;

public enum PlaceHubRole { OfficeManager, LocationManager, SystemAdministrator }
public enum RequestState { Draft, Submitted, AwaitingApproval, Approved, Rejected, Running, PendingPropagation, Succeeded, Failed, PartiallyConfigured, RequiresReconciliation }
public enum ResourceKind { DeskPool, ParkingResource, PlacesHierarchy }
public enum OperationKind { Create, Update, ChangeCapacity, ChangeBookingPolicy, Disable, Reconcile }

public sealed record Actor(string Id, PlaceHubRole Role, IReadOnlySet<string> LocationIds);
public sealed record ResourceSpecification(
    ResourceKind ResourceKind, OperationKind Operation, string LocationId, string Building,
    string Floor, string Section, string Name, int Capacity, string? MailboxAlias,
    string PolicyTemplateId = "standard", long ExpectedResourceVersion = 0, PlacesWriteSpec? Places = null)
{
    /// <summary>Builds a Places hierarchy request; <paramref name="locationId"/> is the authorization scope (an assigned building, or the owner-controlled bootstrap scope).</summary>
    public static ResourceSpecification ForPlaces(OperationKind operation, string locationId, PlacesWriteSpec places) =>
        new(ResourceKind.PlacesHierarchy, operation, locationId, "-", "-", "-", places.DisplayName, 1, null, Places: places);
}

public sealed record AuditEntry(DateTimeOffset At, string CorrelationId, string EventCode, RequestState State, int Version);

public sealed class AdministrationRequest
{
    private readonly List<AuditEntry> audit = [];
    public Guid Id { get; } = Guid.NewGuid();
    public string IdempotencyKey { get; }
    public string CorrelationId { get; }
    public ResourceSpecification Specification { get; private set; }
    public RequestState State { get; private set; } = RequestState.Draft;
    public int Version { get; private set; } = 1;
    public string RequestedBy { get; }
    public string? ApprovedBy { get; private set; }
    public int? ApprovedVersion { get; private set; }
    public string? ApprovedPayloadDigest { get; private set; }
    public string? ResultPlaceId { get; private set; }
    public string OutcomeCode { get; private set; } = "REQUEST_DRAFT";
    public IReadOnlyList<AuditEntry> Audit => audit;

    public AdministrationRequest(ResourceSpecification specification, Actor actor, string idempotencyKey, string correlationId)
    {
        ValidateSpecification(specification);
        RequireIdentity(actor);
        RequireLocation(actor, specification.LocationId);
        if (actor.Role is not (PlaceHubRole.OfficeManager or PlaceHubRole.LocationManager or PlaceHubRole.SystemAdministrator))
            throw new AuthorizationException("ROLE_NOT_ALLOWED");
        Specification = specification;
        RequestedBy = actor.Id;
        IdempotencyKey = Required(idempotencyKey, "IDEMPOTENCY_KEY_REQUIRED");
        CorrelationId = Required(correlationId, "CORRELATION_ID_REQUIRED");
        Record("REQUEST_DRAFT");
    }

    public void Edit(ResourceSpecification specification, Actor actor, int expectedVersion)
    {
        EnsureVersion(expectedVersion); RequireIdentity(actor); RequireLocation(actor, Specification.LocationId); RequireLocation(actor, specification.LocationId);
        if (!string.Equals(actor.Id, RequestedBy, StringComparison.OrdinalIgnoreCase)) throw new AuthorizationException("EDIT_OWNER_ONLY");
        if (State is not (RequestState.Draft or RequestState.Rejected)) throw new WorkflowException("REQUEST_IMMUTABLE");
        ValidateSpecification(specification); Specification = specification; ApprovedBy = null; ApprovedVersion = null; ApprovedPayloadDigest = null;
        Version++; State = RequestState.Draft; Record("REQUEST_EDITED");
    }

    public void Submit(Actor actor, int expectedVersion)
    {
        EnsureVersion(expectedVersion); RequireLocation(actor, Specification.LocationId);
        if (State != RequestState.Draft) throw new WorkflowException("SUBMIT_INVALID_STATE");
        State = RequestState.Submitted; Version++; Record("REQUEST_SUBMITTED");
        State = RequestState.AwaitingApproval; Version++; Record("APPROVAL_REQUIRED");
    }

    public void Approve(Actor actor, int expectedVersion)
    {
        EnsureVersion(expectedVersion); RequireIdentity(actor); RequireAdmin(actor); RequireLocation(actor, Specification.LocationId);
        // Four-eyes: requester and approver must be different immutable identities for every request kind and operation.
        if (string.Equals(actor.Id, RequestedBy, StringComparison.OrdinalIgnoreCase)) throw new AuthorizationException("SELF_APPROVAL_DENIED");
        if (State != RequestState.AwaitingApproval) throw new WorkflowException("APPROVE_INVALID_STATE");
        State = RequestState.Approved; ApprovedBy = actor.Id; Version++; ApprovedVersion = Version; ApprovedPayloadDigest = ComputeDigest(Specification); Record("REQUEST_APPROVED");
    }

    public void Reject(Actor actor, int expectedVersion)
    {
        EnsureVersion(expectedVersion); RequireAdmin(actor); RequireLocation(actor, Specification.LocationId);
        if (State != RequestState.AwaitingApproval) throw new WorkflowException("REJECT_INVALID_STATE");
        State = RequestState.Rejected; Version++; Record("REQUEST_REJECTED");
    }

    internal void Start(Actor actor, int expectedVersion)
    {
        EnsureVersion(expectedVersion); RequireIdentity(actor); RequireAdmin(actor); RequireLocation(actor, Specification.LocationId);
        if (State != RequestState.Approved || ApprovedVersion != Version) throw new WorkflowException("APPROVAL_STALE_OR_MISSING");
        VerifyApprovalIntegrity();
        State = RequestState.Running; Version++; Record("MOCK_EXECUTION_STARTED");
    }

    internal void Complete(RequestState state, string code, string? placeId = null)
    {
        if (State != RequestState.Running || state is not (RequestState.PendingPropagation or RequestState.Succeeded or RequestState.Failed or RequestState.PartiallyConfigured or RequestState.RequiresReconciliation))
            throw new WorkflowException("WORKER_RESULT_INVALID");
        State = state; Version++; ResultPlaceId = placeId; Record(code);
    }

    /// <summary>Revalidates the immutable approval data. Called by Start and independently by every worker before any execution.</summary>
    public void VerifyApprovalIntegrity()
    {
        if (State is not (RequestState.Approved or RequestState.Running)) throw new WorkflowException("APPROVAL_INTEGRITY_FAILED");
        if (string.IsNullOrWhiteSpace(ApprovedBy) || string.IsNullOrWhiteSpace(RequestedBy) || string.Equals(ApprovedBy, RequestedBy, StringComparison.OrdinalIgnoreCase)) throw new WorkflowException("APPROVAL_INTEGRITY_FAILED");
        if (ApprovedVersion is null || ApprovedPayloadDigest is null || !string.Equals(ApprovedPayloadDigest, ComputeDigest(Specification), StringComparison.Ordinal)) throw new WorkflowException("APPROVAL_INTEGRITY_FAILED");
    }

    private static string ComputeDigest(ResourceSpecification specification) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(specification))));

    private static void RequireIdentity(Actor actor) { if (string.IsNullOrWhiteSpace(actor.Id)) throw new AuthorizationException("IDENTITY_UNKNOWN"); }
    private void EnsureVersion(int expected) { if (expected != Version) throw new WorkflowException("VERSION_CONFLICT"); }
    private void Record(string code) { OutcomeCode = code; audit.Add(new(DateTimeOffset.UtcNow, CorrelationId, code, State, Version)); }
    private static void RequireAdmin(Actor actor) { if (actor.Role != PlaceHubRole.SystemAdministrator) throw new AuthorizationException("ADMIN_ROLE_REQUIRED"); }
    private static void RequireLocation(Actor actor, string location) { if (!actor.LocationIds.Contains(location)) throw new AuthorizationException("LOCATION_OUT_OF_SCOPE"); }
    private static string Required(string value, string code) => string.IsNullOrWhiteSpace(value) ? throw new ValidationException(code) : value;
    private static void ValidateSpecification(ResourceSpecification spec)
    {
        Required(spec.LocationId, "LOCATION_REQUIRED");
        if ((spec.ResourceKind == ResourceKind.PlacesHierarchy) != (spec.Places is not null)) throw new ValidationException("PLACES_PAYLOAD_MISMATCH");
        if (spec.Places is not null) { spec.Places.Validate(spec.Operation); if (spec.Name != spec.Places.DisplayName) throw new ValidationException("PLACES_PAYLOAD_MISMATCH"); return; }
        Required(spec.Building, "BUILDING_REQUIRED"); Required(spec.Name, "NAME_REQUIRED");
        if (spec.Capacity < 1 || spec.Capacity > 500) throw new ValidationException("CAPACITY_OUT_OF_RANGE");
        if (spec.ResourceKind == ResourceKind.DeskPool && (string.IsNullOrWhiteSpace(spec.Floor) || string.IsNullOrWhiteSpace(spec.Section))) throw new ValidationException("WORKSPACE_PARENT_REQUIRED");
        if (spec.MailboxAlias is { Length: > 0 } alias && (!alias.All(c => char.IsLetterOrDigit(c) || c == '-') || alias.Length > 64)) throw new ValidationException("MAILBOX_ALIAS_INVALID");
        if (spec.PolicyTemplateId is not ("standard" or "restricted")) throw new ValidationException("POLICY_TEMPLATE_NOT_ALLOWED");
    }
}

public class WorkflowException(string code) : Exception(code) { public string Code { get; } = code; }
public sealed class AuthorizationException(string code) : WorkflowException(code);
public sealed class ValidationException(string code) : WorkflowException(code);
