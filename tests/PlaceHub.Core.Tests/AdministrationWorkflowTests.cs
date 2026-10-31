using PlaceHub.Core;
using Xunit;

namespace PlaceHub.Core.Tests;

public sealed class AdministrationWorkflowTests
{
    private static Actor Office(string location="BER") => new("office",PlaceHubRole.OfficeManager,new HashSet<string>{location});
    private static Actor Admin(params string[] locations) => new("admin",PlaceHubRole.SystemAdministrator,new HashSet<string>(locations.Length==0?["BER"]:locations));
    private static ResourceSpecification Spec(string location="BER",string name="Nord") => new(ResourceKind.DeskPool,OperationKind.Create,location,"Berlin","3","Nord",name,12,"workspace-nord");

    [Fact] public void OfficeManagerWithoutExchangeRoleCanSubmit()
    { var r=new AdministrationRequest(Spec(),Office(),"key-1","cor-1");r.Submit(Office(),r.Version);Assert.Equal(RequestState.AwaitingApproval,r.State); }

    [Fact] public void AppAdministratorCanApproveWithoutExchangeRole()
    { var r=new AdministrationRequest(Spec(),Office(),"key-2","cor-2");r.Submit(Office(),r.Version);r.Approve(Admin(),r.Version);Assert.Equal(RequestState.Approved,r.State); }

    [Fact] public void AppAdministratorCanRejectWithoutExecution()
    { var r=new AdministrationRequest(Spec(),Office(),"key-reject","cor-reject");r.Submit(Office(),r.Version);r.Reject(Admin(),r.Version);Assert.Equal(RequestState.Rejected,r.State);Assert.Equal("REQUEST_REJECTED",r.OutcomeCode); }

    [Fact] public async Task UnapprovedRequestCannotExecute()
    { var service=Service(out _);var r=service.Create(Spec(),Office(),"key-3");await Assert.ThrowsAsync<WorkflowException>(()=>service.ExecuteAsync(r.Id,Admin(),r.Version)); }

    [Fact] public void CrossLocationApprovalIsDenied()
    { var r=new AdministrationRequest(Spec("BER"),Office(),"key-4","cor-4");r.Submit(Office(),r.Version);var ex=Assert.Throws<AuthorizationException>(()=>r.Approve(Admin("HAM"),r.Version));Assert.Equal("LOCATION_OUT_OF_SCOPE",ex.Code); }

    [Fact] public void ApprovedRequestCannotBeModified()
    { var r=new AdministrationRequest(Spec(),Office(),"key-5","cor-5");r.Submit(Office(),r.Version);r.Approve(Admin(),r.Version);Assert.Throws<WorkflowException>(()=>r.Edit(Spec(name:"changed"),Office(),r.Version)); }

    [Fact] public void StaleApprovalVersionCannotReplay()
    { var r=new AdministrationRequest(Spec(),Office(),"key-6","cor-6");r.Submit(Office(),r.Version);var stale=r.Version;r.Approve(Admin(),stale);Assert.Throws<WorkflowException>(()=>r.Approve(Admin(),stale)); }

    [Fact] public void DuplicateIdempotencyKeyIsRejected()
    { var service=Service(out _);service.Create(Spec(),Office(),"same");var ex=Assert.Throws<WorkflowException>(()=>service.Create(Spec(name:"Other"),Office(),"same"));Assert.Equal("DUPLICATE_REQUEST",ex.Code); }

    [Fact] public async Task MockWorkerCompletesApprovedTypedOperation()
    { var service=Service(out _);var r=service.Create(Spec(),Office(),"key-7");r.Submit(Office(),r.Version);r.Approve(Admin(),r.Version);await service.ExecuteAsync(r.Id,Admin(),r.Version);Assert.Equal(RequestState.Succeeded,r.State);Assert.Equal("MOCK_VERIFIED",r.OutcomeCode); }

    [Fact] public async Task PartialFailureRequiresExplicitReconciliation()
    { var service=Service(out _);var r=service.Create(Spec(name:"TeilFehler Pool"),Office(),"key-8");r.Submit(Office(),r.Version);r.Approve(Admin(),r.Version);await service.ExecuteAsync(r.Id,Admin(),r.Version);Assert.Equal(RequestState.PartiallyConfigured,r.State);Assert.Throws<WorkflowException>(()=>r.Approve(Admin(),r.Version)); }

    [Fact] public void UnapprovedPolicyParameterIsRejected()
    { var bad=Spec() with { PolicyTemplateId="$(Invoke-Expression)" };Assert.Throws<ValidationException>(()=>new AdministrationRequest(bad,Office(),"key-9","cor-9")); }

    [Fact] public void MailboxCommandInjectionIsRejected()
    { var bad=Spec() with { MailboxAlias="pool;Remove-Mailbox" };Assert.Throws<ValidationException>(()=>new AdministrationRequest(bad,Office(),"key-10","cor-10")); }

    [Fact] public void OfflineMockHasNoTenantAccess()
    { Assert.False(OfflineMockProvisioningWorker.TenantAccessEnabled); }

    private static AdministrationService Service(out InMemoryAdministrationRepository repo){repo=new();return new(repo,new OfflineMockProvisioningWorker());}
}
