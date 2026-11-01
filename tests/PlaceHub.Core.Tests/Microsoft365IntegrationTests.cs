using System.Net;
using System.Text;
using PlaceHub.Core;
using Xunit;

namespace PlaceHub.Core.Tests;

public sealed class Microsoft365IntegrationTests
{
    private static Microsoft365Options LiveOptions => new() { Mode=IntegrationMode.Microsoft365ReadOnly,TenantId="11111111-1111-1111-1111-111111111111",ClientId="22222222-2222-2222-2222-222222222222",CredentialProvider="Certificate",ClientCertificatePath=typeof(Microsoft365IntegrationTests).Assembly.Location };
    private static ReadAuthorizationContext LiveAuth(IReadOnlySet<string>? scopes=null,IReadOnlySet<string>? locations=null,IReadOnlySet<string>? mailboxes=null) => new("11111111-1111-1111-1111-111111111111","subject",PlaceHubRole.OfficeManager,locations??new HashSet<string>{"building-1"},scopes??new HashSet<string>{"Place.Read.All","Calendars.ReadBasic"},mailboxes??new HashSet<string>(StringComparer.OrdinalIgnoreCase){"p101@example.invalid"},false);

    [Fact] public void OfflineModeNeedsExplicitSyntheticProfile() => Microsoft365Configuration.Validate(new(){AllowSyntheticData=true});

    [Fact] public void OfflineModeWithoutExplicitProfileFailsClosed()
    { var ex=Assert.Throws<IntegrationConfigurationException>(()=>Microsoft365Configuration.Validate(new()));Assert.Equal("SYNTHETIC_PROFILE_NOT_EXPLICITLY_ENABLED",ex.Code); }

    [Fact] public void OfflineModeRejectsLiveIdentityOrCredentialConfiguration()
    { var ex=Assert.Throws<IntegrationConfigurationException>(()=>Microsoft365Configuration.Validate(new(){AllowSyntheticData=true,TenantId=Guid.NewGuid().ToString()}));Assert.Equal("MOCK_LIVE_CONFIGURATION_CONFLICT",ex.Code); }

    [Fact] public void ReadOnlyModeFailsClosedWithoutCredential()
    { var options=new Microsoft365Options{Mode=IntegrationMode.Microsoft365ReadOnly,TenantId=Guid.NewGuid().ToString(),ClientId=Guid.NewGuid().ToString()};var ex=Assert.Throws<IntegrationConfigurationException>(()=>Microsoft365Configuration.Validate(options));Assert.Equal("CONFIDENTIAL_CLIENT_CREDENTIAL_UNAVAILABLE",ex.Code); }

    [Fact] public void MockIdentityCannotUseLiveAuthorization()
    { var auth=LiveAuth() with { IsSyntheticIdentity=true };var ex=Assert.Throws<IntegrationAuthorizationException>(()=>auth.Demand("Place.Read.All","building-1"));Assert.Equal("MOCK_IDENTITY_DENIED_FROM_LIVE_MODE",ex.Code); }

    [Fact] public void MissingRoleLocationAndScopeAreDenied()
    { Assert.Equal("APPLICATION_ROLE_MISSING",Assert.Throws<IntegrationAuthorizationException>(()=>(LiveAuth() with { Role=null }).Demand("Place.Read.All","building-1")).Code);Assert.Equal("LOCATION_OUT_OF_SCOPE",Assert.Throws<IntegrationAuthorizationException>(()=>LiveAuth().Demand("Place.Read.All","other")).Code);Assert.Equal("DELEGATED_SCOPE_MISSING",Assert.Throws<IntegrationAuthorizationException>(()=>LiveAuth(new HashSet<string>()).Demand("Place.Read.All","building-1")).Code); }

    [Fact] public void WrongTenantIsDenied()
    { var ex=Assert.Throws<IntegrationAuthorizationException>(()=>(LiveAuth() with { TenantId="33333333-3333-3333-3333-333333333333" }).DemandTenant(LiveOptions.TenantId));Assert.Equal("TENANT_MISMATCH",ex.Code); }

    [Fact] public async Task OfflinePlacesUsesNoHttpAndPreservesHierarchy()
    { var reader=new OfflinePlacesReader();var actor=new ReadAuthorizationContext("offline","office",PlaceHubRole.OfficeManager,new HashSet<string>{"BER"},new HashSet<string>(),new HashSet<string>(),true);var snapshot=await reader.ReadHierarchyAsync(actor,default);Assert.Equal("OfflineMock",snapshot.DataSource);Assert.Contains(snapshot.Places,x=>x.Type==PlaceType.Workspace);Assert.All(snapshot.Places,x=>Assert.Equal("OfflineMock",x.DataSource)); }

    [Fact] public async Task GraphPlacesReadsAllTypesPagesAndFiltersUnauthorizedLocation()
    {
        var calls=0;var handler=new StubHandler(request=>{calls++;var path=request.RequestUri!.AbsolutePath;var query=request.RequestUri.Query;if(path.EndsWith("microsoft.graph.building")&&query.Contains("skip"))return Json("{\"value\":[]}");if(path.EndsWith("microsoft.graph.building")){return Json("{\"value\":[{\"id\":\"building-1\",\"placeId\":\"building-1\",\"displayName\":\"Berlin\"},{\"id\":\"building-2\",\"placeId\":\"building-2\",\"displayName\":\"Secret\"}],\"@odata.nextLink\":\"https://graph.microsoft.com/v1.0/places/microsoft.graph.building?$skip=2\"}");}if(path.EndsWith("microsoft.graph.floor"))return Json("{\"value\":[{\"id\":\"floor-1\",\"parentId\":\"building-1\",\"displayName\":\"3\"},{\"id\":\"floor-2\",\"parentId\":\"building-2\",\"displayName\":\"9\"}]}");if(path.EndsWith("microsoft.graph.section"))return Json("{\"value\":[{\"id\":\"section-1\",\"parentId\":\"floor-1\",\"displayName\":\"Nord\"}]}");if(path.EndsWith("microsoft.graph.workspace"))return Json("{\"value\":[{\"id\":\"workspace-1\",\"parentId\":\"section-1\",\"displayName\":\"Fokus\",\"capacity\":12,\"emailAddress\":\"focus@example.invalid\"}]}");return Json("{\"value\":[]}");});
        var reader=new GraphPlacesReader(Client(handler),new FixedTokenProvider(),LiveOptions);var snapshot=await reader.ReadHierarchyAsync(LiveAuth(),default);Assert.Contains(snapshot.Places,x=>x.Id=="workspace-1"&&x.Capacity==12);Assert.DoesNotContain(snapshot.Places,x=>x.Id is "building-2" or "floor-2");Assert.True(calls>=6);
    }

    [Fact] public async Task GraphPlacesResolvesParentsByStablePlaceIdAndAuthorizesByEither()
    {
        var handler=new StubHandler(request=>{var path=request.RequestUri!.AbsolutePath;
            if(path.EndsWith("microsoft.graph.building"))return Json("{\"value\":[{\"id\":\"b-mutable\",\"placeId\":\"b-stable\",\"displayName\":\"Berlin\",\"lastUpdatedTime\":\"2026-10-01T08:00:00Z\"}]}");
            if(path.EndsWith("microsoft.graph.floor"))return Json("{\"value\":[{\"id\":\"f-1\",\"placeId\":\"f-stable\",\"parentId\":\"b-stable\",\"displayName\":\"3\"}]}");
            if(path.EndsWith("microsoft.graph.section"))return Json("{\"value\":[{\"id\":\"s-1\",\"parentId\":\"f-1\",\"displayName\":\"Nord\"}]}");
            return Json("{\"value\":[]}");});
        var reader=new GraphPlacesReader(Client(handler),new FixedTokenProvider(),LiveOptions);
        var snapshot=await reader.ReadHierarchyAsync(LiveAuth(locations:new HashSet<string>{"b-stable"}),default);
        Assert.Equal(["b-mutable","f-1","s-1"],snapshot.Places.Select(x=>x.Id).ToArray());
        Assert.Equal("b-mutable",snapshot.Places.Single(x=>x.Id=="f-1").ParentId);
        Assert.Equal(DateTimeOffset.Parse("2026-10-01T08:00:00Z"),snapshot.Places[0].SourceUpdatedAt);
    }

    [Fact] public async Task GraphPlacesTranslatesForbidden()
    { var reader=new GraphPlacesReader(Client(new StubHandler(_=>new(HttpStatusCode.Forbidden))),new FixedTokenProvider(),LiveOptions);var ex=await Assert.ThrowsAsync<IntegrationException>(()=>reader.ReadHierarchyAsync(LiveAuth(),default));Assert.Equal("GRAPH_PERMISSION_DENIED",ex.Code); }

    [Fact] public async Task GraphPlacesRetriesThrottleThenSucceeds()
    { var calls=0;var reader=new GraphPlacesReader(Client(new StubHandler(_=>++calls==1?new(HttpStatusCode.TooManyRequests){Headers={RetryAfter=new System.Net.Http.Headers.RetryConditionHeaderValue(TimeSpan.Zero)}}:Json("{\"value\":[]}"))),new FixedTokenProvider(),LiveOptions);await reader.ReadHierarchyAsync(LiveAuth(),default);Assert.True(calls>=6); }

    [Fact] public async Task GraphPlacesRejectsUntrustedNextLink()
    { var reader=new GraphPlacesReader(Client(new StubHandler(_=>Json("{\"value\":[],\"@odata.nextLink\":\"https://evil.invalid/v1.0/places/x\"}"))),new FixedTokenProvider(),LiveOptions);var ex=await Assert.ThrowsAsync<IntegrationException>(()=>reader.ReadHierarchyAsync(LiveAuth(),default));Assert.Equal("GRAPH_NEXT_LINK_REJECTED",ex.Code); }

    [Fact] public async Task GraphPlacesReportsUnavailableAfterBoundedRetry()
    { var calls=0;var reader=new GraphPlacesReader(Client(new StubHandler(_=>{calls++;return new(HttpStatusCode.ServiceUnavailable){Headers={RetryAfter=new System.Net.Http.Headers.RetryConditionHeaderValue(TimeSpan.Zero)}};})),new FixedTokenProvider(),LiveOptions);var ex=await Assert.ThrowsAsync<IntegrationException>(()=>reader.ReadHierarchyAsync(LiveAuth(),default));Assert.Equal("GRAPH_UNAVAILABLE",ex.Code);Assert.Equal(3,calls); }

    [Fact] public async Task GraphPlacesReportsMissingTenantCapability()
    { var reader=new GraphPlacesReader(Client(new StubHandler(_=>new(HttpStatusCode.NotFound))),new FixedTokenProvider(),LiveOptions);var ex=await Assert.ThrowsAsync<IntegrationException>(()=>reader.ReadHierarchyAsync(LiveAuth(),default));Assert.Equal("TENANT_CAPABILITY_UNAVAILABLE",ex.Code); }

    [Fact] public async Task GraphPlacesPropagatesSafeTokenFailureWithoutHttp()
    { var calls=0;var reader=new GraphPlacesReader(Client(new StubHandler(_=>{calls++;return Json("{}");})),new FailingTokenProvider(),LiveOptions);var ex=await Assert.ThrowsAsync<IntegrationAuthorizationException>(()=>reader.ReadHierarchyAsync(LiveAuth(),default));Assert.Equal("INVALID_TOKEN",ex.Code);Assert.Equal(0,calls); }

    [Fact] public async Task GraphPlacesHonorsCancellation()
    { using var cts=new CancellationTokenSource();cts.Cancel();var reader=new GraphPlacesReader(Client(new StubHandler(_=>Json("{}"))),new FixedTokenProvider(),LiveOptions);await Assert.ThrowsAnyAsync<OperationCanceledException>(()=>reader.ReadHierarchyAsync(LiveAuth(),cts.Token)); }

    [Fact] public async Task AvailabilityReadsOnlyFreeBusyWithoutBookingMutation()
    { HttpRequestMessage? observed=null;var reader=new GraphAvailabilityReader(Client(new StubHandler(request=>{observed=request;return Json("{\"value\":[{\"scheduleId\":\"p101@example.invalid\",\"availabilityView\":\"0000\"}]}");})),new FixedTokenProvider(),LiveOptions);var start=DateTimeOffset.Parse("2026-11-01T08:00:00+01:00");var result=await reader.ReadAsync(new("building-1",["p101@example.invalid"],start,start.AddHours(2),"W. Europe Standard Time"),LiveAuth(),default);Assert.Equal(AvailabilityState.Free,result.Single().State);Assert.Equal(HttpMethod.Post,observed!.Method);Assert.Equal("/v1.0/me/calendar/getSchedule",observed.RequestUri!.AbsolutePath); }

    [Fact] public async Task AvailabilityRejectsMailboxOutsideAuthorizationBeforeHttp()
    { var calls=0;var reader=new GraphAvailabilityReader(Client(new StubHandler(_=>{calls++;return Json("{}");})),new FixedTokenProvider(),LiveOptions);var start=DateTimeOffset.UtcNow;var ex=await Assert.ThrowsAsync<IntegrationAuthorizationException>(()=>reader.ReadAsync(new("building-1",["other@example.invalid"],start,start.AddHours(1),"UTC"),LiveAuth(),default));Assert.Equal("RESOURCE_MAILBOX_OUT_OF_SCOPE",ex.Code);Assert.Equal(0,calls); }

    [Fact] public async Task AvailabilityValidatesIntervalAndCancellation()
    { var reader=new OfflineAvailabilityReader();var start=DateTimeOffset.UtcNow;await Assert.ThrowsAsync<ValidationException>(()=>reader.ReadAsync(new("BER",["p@example.invalid"],start,start,"UTC"),LiveAuth(),default));using var cts=new CancellationTokenSource();cts.Cancel();await Assert.ThrowsAsync<OperationCanceledException>(()=>reader.ReadAsync(new("BER",["p@example.invalid"],start,start.AddHours(1),"UTC"),LiveAuth(),cts.Token)); }

    private static HttpClient Client(HttpMessageHandler handler)=>new(handler){BaseAddress=new("https://graph.microsoft.com/v1.0/")};
    private static HttpResponseMessage Json(string json)=>new(HttpStatusCode.OK){Content=new StringContent(json,Encoding.UTF8,"application/json")};
    private sealed class FixedTokenProvider : IDelegatedTokenProvider { public Task<string> GetTokenAsync(IReadOnlySet<string> scopes,CancellationToken cancellationToken)=>Task.FromResult("test-token-not-logged"); }
    private sealed class FailingTokenProvider : IDelegatedTokenProvider { public Task<string> GetTokenAsync(IReadOnlySet<string> scopes,CancellationToken cancellationToken)=>throw new IntegrationAuthorizationException("INVALID_TOKEN"); }
    private sealed class StubHandler(Func<HttpRequestMessage,HttpResponseMessage> handler) : HttpMessageHandler { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken cancellationToken){cancellationToken.ThrowIfCancellationRequested();return Task.FromResult(handler(request));} }
}
