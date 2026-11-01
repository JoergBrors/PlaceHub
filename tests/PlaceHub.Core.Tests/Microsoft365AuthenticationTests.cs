using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using PlaceHub.Core;
using PlaceHub.Web;
using Xunit;

namespace PlaceHub.Core.Tests;

public sealed class Microsoft365AuthenticationTests
{
    private const string Tenant = "11111111-1111-1111-1111-111111111111";
    private const string Subject = "22222222-2222-2222-2222-222222222222";
    private static Microsoft365Options Options => new() { Mode=IntegrationMode.Microsoft365ReadOnly,TenantId=Tenant,ClientId="33333333-3333-3333-3333-333333333333",CredentialProvider="Certificate",ClientCertificatePath=typeof(Microsoft365AuthenticationTests).Assembly.Location };

    [Fact]
    public void ValidTenantRoleAndLocationBuildLeastPrivilegeContext()
    {
        var actor = Create([Claim("tid",Tenant),Claim("oid",Subject),Claim("roles","PlaceHub.OfficeManager"),("name","Office Manager")], new() { [$"PlaceHub:LocationAssignments:{Subject}:0"]="building-1" });
        var context = actor.CreateReadContext(Options);
        Assert.Equal(PlaceHubRole.OfficeManager, actor.Current.Role);
        Assert.Contains("building-1", context.LocationIds);
        Assert.False(context.IsSyntheticIdentity);
    }

    [Fact]
    public void WrongTenantIsRejected() => Assert.Equal("TENANT_MISMATCH", Assert.Throws<IntegrationAuthorizationException>(() => Create([Claim("tid",Guid.NewGuid().ToString()),Claim("oid",Subject),Claim("roles","PlaceHub.OfficeManager")], new())).Code);

    [Fact]
    public void MissingRoleIsRejected() => Assert.Equal("APPLICATION_ROLE_MISSING", Assert.Throws<IntegrationAuthorizationException>(() => Create([Claim("tid",Tenant),Claim("oid",Subject)], new())).Code);

    [Fact]
    public void MissingLocationIsRejected() => Assert.Equal("LOCATION_ASSIGNMENT_MISSING", Assert.Throws<IntegrationAuthorizationException>(() => Create([Claim("tid",Tenant),Claim("oid",Subject),Claim("roles","PlaceHub.OfficeManager")], new())).Code);

    [Fact]
    public void MultipleRolesAreRejected() => Assert.Equal("APPLICATION_ROLE_AMBIGUOUS", Assert.Throws<IntegrationAuthorizationException>(() => Create([Claim("tid",Tenant),Claim("oid",Subject),Claim("roles","PlaceHub.OfficeManager"),Claim("roles","PlaceHub.SystemAdministrator")], new())).Code);

    [Fact]
    public void DeniedUserDoesNotCrashComponentConstructionAndFailsOnUse()
    {
        var accessor = new HttpContextAccessor { HttpContext = new DefaultHttpContext { User = new ClaimsPrincipal(new ClaimsIdentity([new Claim("tid",Tenant),new Claim("oid",Subject)],"test")) } };
        var actor = CurrentActorContext.CreateForRequest(accessor, new ConfigurationBuilder().Build(), Options, null);
        Assert.Equal("APPLICATION_ROLE_MISSING", actor.DenialCode);
        Assert.Equal("APPLICATION_ROLE_MISSING", Assert.Throws<IntegrationAuthorizationException>(() => actor.Current).Code);
    }

    private static CurrentActorContext Create((string Type,string Value)[] claims, Dictionary<string,string?> values)
    {
        var identity = new ClaimsIdentity(claims.Select(x=>new Claim(x.Type,x.Value)), "test", "name", "roles");
        var context = new DefaultHttpContext { User = new ClaimsPrincipal(identity) };
        var accessor = new HttpContextAccessor { HttpContext = context };
        var configuration = new ConfigurationBuilder().AddInMemoryCollection(values).Build();
        return new(accessor,configuration,Options);
    }
    private static (string,string) Claim(string type,string value)=>(type,value);
}
