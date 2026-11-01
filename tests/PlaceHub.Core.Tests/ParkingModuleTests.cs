using PlaceHub.Core;
using Xunit;

namespace PlaceHub.Core.Tests;

public sealed class ParkingModuleTests
{
    private const string Address = "ph-park-01@contoso.example";
    private static Actor Office(string location = "BER") => new("office", PlaceHubRole.OfficeManager, new HashSet<string> { location });
    private static Actor Admin() => new("admin", PlaceHubRole.SystemAdministrator, new HashSet<string> { "BER" });

    private static (ParkingService Parking, AdministrationService Admin) Services()
    {
        var administration = new AdministrationService(new InMemoryAdministrationRepository(), new DisabledProvisioningWorker());
        return (new ParkingService(new InMemoryParkingRepository(), administration), administration);
    }

    [Fact]
    public void RegisteringAnExistingMailboxCreatesAPendingSpaceAndAVerificationRequest()
    {
        var (parking, administration) = Services();
        var (space, request) = parking.RegisterExisting(Office(), "BER", Address, "Parkplatz 01", ParkingCategory.Standard, false, false);
        Assert.Equal(ParkingStatus.PendingVerification, space.Status);
        Assert.Equal(OperationKind.Reconcile, request.Specification.Operation);
        Assert.Equal(RequestState.AwaitingApproval, request.State);
        Assert.Equal(Address, space.MailboxAddress);
        Assert.Single(parking.List(Office()));
        Assert.Single(administration.List(Office()));
    }

    [Fact]
    public void ParkingSpacesAreLocationScoped()
    {
        var (parking, _) = Services();
        var (space, _) = parking.RegisterExisting(Office(), "BER", Address, "P1", ParkingCategory.Standard, false, false);
        var other = Office("HAM");
        Assert.Empty(parking.List(other));
        Assert.Equal("LOCATION_OUT_OF_SCOPE", Assert.Throws<AuthorizationException>(() => parking.Get(space.Id, other)).Code);
        Assert.Equal("LOCATION_OUT_OF_SCOPE", Assert.Throws<AuthorizationException>(() => parking.RegisterExisting(other, "BER", "x-1@contoso.example", "P", ParkingCategory.Standard, false, false)).Code);
        Assert.Equal("LOCATION_OUT_OF_SCOPE", Assert.Throws<AuthorizationException>(() => parking.RequestDisable(other, space.Id)).Code);
        Assert.Equal("LOCATION_OUT_OF_SCOPE", Assert.Throws<AuthorizationException>(() => parking.RequestBookingPolicy(other, space.Id, "standard")).Code);
    }

    [Fact]
    public void ADuplicateMailboxCannotBeRegisteredTwiceRegardlessOfCase()
    {
        var (parking, _) = Services();
        parking.RegisterExisting(Office(), "BER", Address, "P1", ParkingCategory.Standard, false, false);
        Assert.Equal("PARKING_MAILBOX_ALREADY_REGISTERED", Assert.Throws<WorkflowException>(() => parking.RegisterExisting(Office(), "BER", Address, "P1 again", ParkingCategory.Standard, false, false)).Code);
    }

    [Theory]
    [InlineData("not-an-address", "P1", "MAILBOX_ADDRESS_INVALID")]
    [InlineData("a@contoso.example;calc", "P1", "MAILBOX_ADDRESS_INVALID")]
    [InlineData(Address, "", "PARKING_DISPLAY_NAME_INVALID")]
    public void InvalidInputIsRejectedBeforeAnythingIsStored(string address, string name, string code)
    {
        var (parking, administration) = Services();
        Assert.Equal(code, Assert.Throws<ValidationException>(() => parking.RegisterExisting(Office(), "BER", address, name, ParkingCategory.Standard, false, false)).Code);
        Assert.Empty(parking.List(Office())); Assert.Empty(administration.List(Office()));
    }

    [Fact]
    public void CategoriesImplyTheirAccessibilityAndChargingFlags()
    {
        var (parking, _) = Services();
        var (accessible, _) = parking.RegisterExisting(Office(), "BER", "a-1@contoso.example", "A", ParkingCategory.Accessible, false, false);
        var (ev, _) = parking.RegisterExisting(Office(), "BER", "e-1@contoso.example", "E", ParkingCategory.ElectricVehicle, false, false);
        Assert.True(accessible.Accessible); Assert.True(ev.EvCharging);
    }

    [Fact]
    public void MetadataEditsAreLocalAndDoNotCreateExchangeRequests()
    {
        var (parking, administration) = Services();
        var (space, _) = parking.RegisterExisting(Office(), "BER", Address, "P1", ParkingCategory.Standard, false, false);
        var before = administration.List(Office()).Count;
        var updated = parking.UpdateMetadata(Office(), space.Id, ParkingCategory.Visitor, true, true);
        Assert.Equal((ParkingCategory.Visitor, true, true), (updated.Category, updated.Accessible, updated.EvCharging));
        Assert.Equal(before, administration.List(Office()).Count);
    }

    [Fact]
    public void BookingPolicyAndDisableAreTypedRequestsNeverDirectChanges()
    {
        var (parking, administration) = Services();
        var (space, _) = parking.RegisterExisting(Office(), "BER", Address, "P1", ParkingCategory.Standard, false, false);
        var policy = parking.RequestBookingPolicy(Office(), space.Id, "restricted");
        Assert.Equal(OperationKind.ChangeBookingPolicy, policy.Specification.Operation); Assert.Equal("restricted", policy.Specification.Exchange!.PolicyTemplateId);
        Assert.Throws<ValidationException>(() => parking.RequestBookingPolicy(Office(), space.Id, "open"));
        var disable = parking.RequestDisable(Office(), space.Id);
        Assert.Equal(OperationKind.Disable, disable.Specification.Operation);
        Assert.All(administration.List(Office()), r => Assert.Equal(RequestState.AwaitingApproval, r.State));
    }

    [Fact]
    public void CreationRequestsRecordTheRequestedMailboxButProvisionNothing()
    {
        var (parking, _) = Services();
        var spec = new ExchangeSpec(Address, "PH-PARK-01", "ph-park-01", "Parkplatz 01", ParkingMailboxType.Equipment);
        var (space, request) = parking.RequestCreate(Office(), "BER", spec, ParkingCategory.Standard, false, false);
        Assert.Equal(ParkingStatus.Provisioning, space.Status); Assert.Equal(OperationKind.Create, request.Specification.Operation);
    }

    [Fact]
    public async Task WorkerOutcomesAreMirroredIntoTheBusinessStatus()
    {
        var administration = new AdministrationService(new InMemoryAdministrationRepository(), new StubWorker(new ProvisioningResult(RequestState.Succeeded, "MAILBOX_STATE_VERIFIED")));
        var parking = new ParkingService(new InMemoryParkingRepository(), administration);
        var (space, request) = parking.RegisterExisting(Office(), "BER", Address, "P1", ParkingCategory.Standard, false, false);
        request.Approve(Admin(), request.Version);
        await administration.ExecuteAsync(request.Id, Admin(), request.Version);
        var refreshed = parking.Get(space.Id, Office());
        Assert.Equal(ParkingStatus.Active, refreshed.Status); Assert.NotNull(refreshed.LastVerifiedAt); Assert.Equal("MAILBOX_STATE_VERIFIED", refreshed.OutcomeCode);
    }

    [Theory]
    [InlineData(RequestState.RequiresReconciliation, ParkingStatus.RequiresReconciliation)]
    [InlineData(RequestState.Failed, ParkingStatus.Failed)]
    public async Task AmbiguousOrFailedOutcomesAreNeverShownAsActive(RequestState state, ParkingStatus expected)
    {
        var administration = new AdministrationService(new InMemoryAdministrationRepository(), new StubWorker(new ProvisioningResult(state, "X")));
        var parking = new ParkingService(new InMemoryParkingRepository(), administration);
        var (space, request) = parking.RegisterExisting(Office(), "BER", Address, "P1", ParkingCategory.Standard, false, false);
        request.Approve(Admin(), request.Version); await administration.ExecuteAsync(request.Id, Admin(), request.Version);
        Assert.Equal(expected, parking.Get(space.Id, Office()).Status);
    }

    private sealed class StubWorker(ProvisioningResult result) : IProvisioningWorker
    {
        public Task<ProvisioningResult> ExecuteAsync(AdministrationRequest request, CancellationToken cancellationToken) => Task.FromResult(result);
    }
}
