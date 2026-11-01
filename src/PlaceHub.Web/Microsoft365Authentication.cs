using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.Identity.Web;
using PlaceHub.Core;

namespace PlaceHub.Web;

public sealed class CurrentActorContext
{
    private static readonly IReadOnlyDictionary<string, PlaceHubRole> Roles = new Dictionary<string, PlaceHubRole>(StringComparer.Ordinal)
    {
        ["PlaceHub.OfficeManager"] = PlaceHubRole.OfficeManager,
        ["PlaceHub.LocationManager"] = PlaceHubRole.LocationManager,
        ["PlaceHub.SystemAdministrator"] = PlaceHubRole.SystemAdministrator
    };

    private readonly Actor? actor;
    private readonly string? denialCode;

    // Blazor Server circuits have no HttpContext after the prerender pass; the circuit's
    // authentication state (already completed when components are created) is the source there.
    private static ClaimsPrincipal? ResolvePrincipal(IHttpContextAccessor accessor, AuthenticationStateProvider? provider)
    {
        var fromHttp = accessor.HttpContext?.User;
        if (fromHttp?.Identity?.IsAuthenticated == true) return fromHttp;
        var task = provider?.GetAuthenticationStateAsync();
        return task is { IsCompletedSuccessfully: true } ? task.Result.User : fromHttp;
    }

    /// <summary>Creates the context for DI; denials are deferred to <see cref="Current"/> so one unauthorized user cannot crash component construction.</summary>
    public static CurrentActorContext CreateForRequest(IHttpContextAccessor accessor, IConfiguration configuration, Microsoft365Options options, AuthenticationStateProvider? provider)
    {
        try { return new CurrentActorContext(accessor, configuration, options, provider); }
        catch (IntegrationAuthorizationException ex) { return new CurrentActorContext(ResolvePrincipal(accessor, provider) ?? new ClaimsPrincipal(new ClaimsIdentity()), ex.Code); }
    }

    private CurrentActorContext(ClaimsPrincipal principal, string denial) { Principal = principal; denialCode = denial; }

    public CurrentActorContext(IHttpContextAccessor accessor, IConfiguration configuration, Microsoft365Options options, AuthenticationStateProvider? stateProvider = null)
    {
        var principal = ResolvePrincipal(accessor, stateProvider) ?? throw new IntegrationAuthorizationException("AUTHENTICATED_PRINCIPAL_MISSING");
        if (options.Mode == IntegrationMode.OfflineMock)
        {
            Principal = principal;
            actor = new("synthetic-test", PlaceHubRole.OfficeManager, new HashSet<string> { "BER" });
            IsSynthetic = true;
            return;
        }

        if (principal.Identity?.IsAuthenticated != true) throw new IntegrationAuthorizationException("AUTHENTICATION_REQUIRED");
        var tenant = principal.FindFirstValue("tid");
        if (!string.Equals(tenant, options.TenantId, StringComparison.OrdinalIgnoreCase)) throw new IntegrationAuthorizationException("TENANT_MISMATCH");
        var subject = principal.FindFirstValue("oid") ?? throw new IntegrationAuthorizationException("SUBJECT_ID_MISSING");
        var roleValues = principal.FindAll("roles").Select(x => x.Value).Where(Roles.ContainsKey).Distinct(StringComparer.Ordinal).ToArray();
        if (roleValues.Length != 1) throw new IntegrationAuthorizationException(roleValues.Length == 0 ? "APPLICATION_ROLE_MISSING" : "APPLICATION_ROLE_AMBIGUOUS");
        var locations = configuration.GetSection($"PlaceHub:LocationAssignments:{subject}").Get<string[]>() ?? [];
        var safeLocations = new HashSet<string>(locations.Where(IsValidLocation), StringComparer.OrdinalIgnoreCase);
        if (safeLocations.Count == 0) throw new IntegrationAuthorizationException("LOCATION_ASSIGNMENT_MISSING");
        Principal = principal;
        actor = new(subject, Roles[roleValues[0]], safeLocations);
    }

    public ClaimsPrincipal Principal { get; }
    public string? DenialCode => denialCode;
    public Actor Current => actor ?? throw new IntegrationAuthorizationException(denialCode ?? "AUTHENTICATION_REQUIRED");
    public bool IsSynthetic { get; }
    private static bool IsValidLocation(string value) => !string.IsNullOrWhiteSpace(value) && value.Length <= 128 && value.All(x => char.IsLetterOrDigit(x) || x is '-' or '_' or '.');

    public ReadAuthorizationContext CreateReadContext(Microsoft365Options options, IEnumerable<string>? mailboxes = null) =>
        new(options.TenantId, Current.Id, Current.Role, Current.LocationIds,
            new HashSet<string>(["Place.Read.All", "Calendars.ReadBasic"], StringComparer.Ordinal),
            new HashSet<string>(mailboxes ?? [], StringComparer.OrdinalIgnoreCase), IsSynthetic);
}

public sealed class MicrosoftIdentityDelegatedTokenProvider(
    ITokenAcquisition acquisition,
    CurrentActorContext actor,
    Microsoft365Options options) : IDelegatedTokenProvider
{
    private const string GraphAudience = "00000003-0000-0000-c000-000000000000";

    public async Task<string> GetTokenAsync(IReadOnlySet<string> scopes, CancellationToken cancellationToken)
    {
        if (actor.IsSynthetic) throw new IntegrationAuthorizationException("MOCK_IDENTITY_DENIED_FROM_LIVE_MODE");
        if (scopes.Count == 0 || scopes.Any(x => x is not ("Place.Read.All" or "Calendars.ReadBasic"))) throw new IntegrationAuthorizationException("DELEGATED_SCOPE_NOT_ALLOWED");
        string token;
        try
        {
            token = await acquisition.GetAccessTokenForUserAsync(scopes, user: actor.Principal);
        }
        catch (MicrosoftIdentityWebChallengeUserException)
        {
            throw new IntegrationAuthorizationException("CONSENT_OR_LOGIN_REQUIRED");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            throw new IntegrationAuthorizationException("TOKEN_ACQUISITION_FAILED");
        }

        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);
        var tenant = jwt.Claims.FirstOrDefault(x => x.Type == "tid")?.Value;
        var subject = jwt.Claims.FirstOrDefault(x => x.Type == "oid")?.Value;
        var granted = new HashSet<string>((jwt.Claims.FirstOrDefault(x => x.Type == "scp")?.Value ?? "").Split(' ', StringSplitOptions.RemoveEmptyEntries), StringComparer.Ordinal);
        if (!string.Equals(tenant, options.TenantId, StringComparison.OrdinalIgnoreCase)) throw new IntegrationAuthorizationException("TOKEN_TENANT_MISMATCH");
        if (!string.Equals(subject, actor.Current.Id, StringComparison.OrdinalIgnoreCase)) throw new IntegrationAuthorizationException("TOKEN_SUBJECT_MISMATCH");
        if (!jwt.Audiences.Contains(GraphAudience, StringComparer.Ordinal) && !jwt.Audiences.Contains("https://graph.microsoft.com", StringComparer.OrdinalIgnoreCase)) throw new IntegrationAuthorizationException("TOKEN_AUDIENCE_INVALID");
        if (!scopes.All(granted.Contains)) throw new IntegrationAuthorizationException("EFFECTIVE_SCOPE_MISSING");
        cancellationToken.ThrowIfCancellationRequested();
        return token;
    }
}
