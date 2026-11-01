using PlaceHub.Core;
using Xunit;

namespace PlaceHub.Core.Tests;

public sealed class FourEyesApprovalTests
{
    private static Actor Office(string id = "office", string location = "BER") => new(id, PlaceHubRole.OfficeManager, new HashSet<string> { location });
    private static Actor Admin(string id, string location = "BER") => new(id, PlaceHubRole.SystemAdministrator, new HashSet<string> { location });
    private static ResourceSpecification Spec(ResourceKind kind = ResourceKind.DeskPool, OperationKind op = OperationKind.Create) =>
        kind == ResourceKind.PlacesHierarchy
            ? ResourceSpecification.ForPlaces(op, "BER", op == OperationKind.Update ? new(PlaceType.Floor, "Nord", null, TargetPlaceId: "floor-1") : new(PlaceType.Floor, "Nord", "building-1"))
            : new(kind, op, "BER", "Berlin", "3", "Nord", "Nord", 12, "workspace-nord");

    private static AdministrationRequest Awaiting(Actor requester, ResourceKind kind = ResourceKind.DeskPool, OperationKind op = OperationKind.Create)
    {
        var request = new AdministrationRequest(Spec(kind, op), requester, Guid.NewGuid().ToString("N"), "cor");
        request.Submit(requester, request.Version);
        return request;
    }

    public static IEnumerable<object[]> AllKindsAndOperations() =>
        from kind in Enum.GetValues<ResourceKind>() from op in Enum.GetValues<OperationKind>()
        where kind != ResourceKind.PlacesHierarchy || op is OperationKind.Create or OperationKind.Update
        select new object[] { kind, op };

    [Theory]
    [InlineData(OperationKind.Disable)] [InlineData(OperationKind.Reconcile)] [InlineData(OperationKind.ChangeCapacity)] [InlineData(OperationKind.ChangeBookingPolicy)]
    public void PlacesHierarchyAllowsOnlyCreateAndUpdate(OperationKind op) =>
        Assert.Equal("PLACES_OPERATION_NOT_ALLOWED", Assert.Throws<ValidationException>(() => new AdministrationRequest(ResourceSpecification.ForPlaces(op, "BER", new(PlaceType.Floor, "F", "b")), Office(), "k", "c")).Code);

    [Theory, MemberData(nameof(AllKindsAndOperations))]
    public void SystemAdministratorCannotApproveOwnRequestForAnyKindOrOperation(ResourceKind kind, OperationKind op)
    {
        var admin = Admin("admin-a");
        var request = Awaiting(admin, kind, op);
        Assert.Equal("SELF_APPROVAL_DENIED", Assert.Throws<AuthorizationException>(() => request.Approve(admin, request.Version)).Code);
        Assert.Equal(RequestState.AwaitingApproval, request.State);
        Assert.Null(request.ApprovedBy);
    }

    [Fact]
    public void SelfApprovalComparisonIgnoresIdentifierCase()
    {
        var request = Awaiting(Admin("ABC-123"));
        Assert.Equal("SELF_APPROVAL_DENIED", Assert.Throws<AuthorizationException>(() => request.Approve(Admin("abc-123"), request.Version)).Code);
    }

    [Theory, MemberData(nameof(AllKindsAndOperations))]
    public async Task IndependentAdministratorApprovalBindsVersionAndDigestAndExecutesOnce(ResourceKind kind, OperationKind op)
    {
        var requester = Office(); var approver = Admin("admin-b");
        var service = new AdministrationService(new InMemoryAdministrationRepository(), new OfflineMockProvisioningWorker());
        var request = service.Create(Spec(kind, op), requester, Guid.NewGuid().ToString("N"));
        request.Submit(requester, request.Version);
        request.Approve(approver, request.Version);
        Assert.Equal("admin-b", request.ApprovedBy);
        Assert.Equal(request.Version, request.ApprovedVersion);
        Assert.False(string.IsNullOrWhiteSpace(request.ApprovedPayloadDigest));
        request.VerifyApprovalIntegrity();
        await service.ExecuteAsync(request.Id, approver, request.Version);
        Assert.Equal(RequestState.Succeeded, request.State);
        var replay = await Assert.ThrowsAsync<WorkflowException>(() => service.ExecuteAsync(request.Id, approver, request.Version));
        Assert.True(replay.Code is "APPROVAL_STALE_OR_MISSING" or "VERSION_CONFLICT");
    }

    [Fact]
    public void UnknownIdentityFailsClosedForCreateApproveAndExecute()
    {
        var unknown = new Actor("", PlaceHubRole.SystemAdministrator, new HashSet<string> { "BER" });
        Assert.Equal("IDENTITY_UNKNOWN", Assert.Throws<AuthorizationException>(() => new AdministrationRequest(Spec(), unknown, "k", "c")).Code);
        var request = Awaiting(Office());
        Assert.Equal("IDENTITY_UNKNOWN", Assert.Throws<AuthorizationException>(() => request.Approve(unknown, request.Version)).Code);
    }

    [Fact]
    public void OnlyTheRequesterMayEditAndEditInvalidatesApprovalMetadata()
    {
        var requester = Office("office-1"); var other = Office("office-2");
        var request = Awaiting(requester);
        request.Reject(Admin("admin-c"), request.Version);
        Assert.Equal("EDIT_OWNER_ONLY", Assert.Throws<AuthorizationException>(() => request.Edit(Spec(op: OperationKind.Update), other, request.Version)).Code);
        request.Edit(Spec(op: OperationKind.Update), requester, request.Version);
        Assert.Null(request.ApprovedBy); Assert.Null(request.ApprovedPayloadDigest); Assert.Null(request.ApprovedVersion);
    }

    [Fact]
    public void ApprovedRequestCannotBeEditedByAnyone()
    {
        var requester = Office(); var approver = Admin("admin-d");
        var request = Awaiting(requester); request.Approve(approver, request.Version);
        Assert.Equal("REQUEST_IMMUTABLE", Assert.Throws<WorkflowException>(() => request.Edit(Spec(op: OperationKind.Disable), requester, request.Version)).Code);
    }

    [Fact]
    public async Task TamperedPayloadAfterApprovalFailsIntegrityAndBlocksStartAndWorker()
    {
        var requester = Office(); var approver = Admin("admin-e");
        var repository = new InMemoryAdministrationRepository();
        var service = new AdministrationService(repository, new OfflineMockProvisioningWorker());
        var request = service.Create(Spec(), requester, Guid.NewGuid().ToString("N"));
        request.Submit(requester, request.Version); request.Approve(approver, request.Version);
        typeof(AdministrationRequest).GetProperty(nameof(AdministrationRequest.Specification))!.GetSetMethod(true)!
            .Invoke(request, [Spec(op: OperationKind.Disable)]);
        Assert.Equal("APPROVAL_INTEGRITY_FAILED", Assert.Throws<WorkflowException>(() => request.VerifyApprovalIntegrity()).Code);
        Assert.Equal("APPROVAL_INTEGRITY_FAILED", (await Assert.ThrowsAsync<WorkflowException>(() => new OfflineMockProvisioningWorker().ExecuteAsync(request, default))).Code);
        Assert.Equal("APPROVAL_INTEGRITY_FAILED", (await Assert.ThrowsAsync<WorkflowException>(() => service.ExecuteAsync(request.Id, approver, request.Version))).Code);
        Assert.Equal(RequestState.Approved, request.State);
    }

    [Fact]
    public async Task WorkerRejectsAnUnapprovedRequestOnItsOwn()
    {
        var request = Awaiting(Office());
        var ex = await Assert.ThrowsAsync<WorkflowException>(() => new OfflineMockProvisioningWorker().ExecuteAsync(request, default));
        Assert.Equal("APPROVAL_INTEGRITY_FAILED", ex.Code);
        Assert.Throws<WorkflowException>(() => request.VerifyApprovalIntegrity());
    }

    [Fact]
    public void CrossLocationAdministratorCannotApprove()
    {
        var request = Awaiting(Office());
        Assert.Equal("LOCATION_OUT_OF_SCOPE", Assert.Throws<AuthorizationException>(() => request.Approve(Admin("admin-f", "HAM"), request.Version)).Code);
    }

    [Fact]
    public void NonAdministratorCannotApproveOrStart()
    {
        var request = Awaiting(Office());
        var manager = new Actor("manager", PlaceHubRole.LocationManager, new HashSet<string> { "BER" });
        Assert.Equal("ADMIN_ROLE_REQUIRED", Assert.Throws<AuthorizationException>(() => request.Approve(manager, request.Version)).Code);
    }

    [Fact]
    public void StaleApprovalVersionCannotBeUsedForApproval()
    {
        var request = Awaiting(Office());
        Assert.Equal("VERSION_CONFLICT", Assert.Throws<WorkflowException>(() => request.Approve(Admin("admin-g"), request.Version - 1)).Code);
    }
}
