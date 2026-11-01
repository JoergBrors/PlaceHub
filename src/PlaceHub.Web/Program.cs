using PlaceHub.Core;
using PlaceHub.Web;
using PlaceHub.Web.Components;
using Microsoft.AspNetCore.Hosting.StaticWebAssets;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Authorization;
using Microsoft.Identity.Web;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;

var builder = WebApplication.CreateBuilder(args);
// Local operators intentionally run the offline POC with Production settings from
// build output. Load the generated manifest explicitly so fingerprinted CSS and
// the Blazor framework assets remain available outside Development and Publish.
StaticWebAssetsLoader.UseStaticWebAssets(builder.Environment, builder.Configuration);
builder.Logging.ClearProviders();
builder.Logging.AddSimpleConsole(options =>
{
    options.SingleLine = true;
    options.TimestampFormat = "yyyy-MM-ddTHH:mm:ssZ ";
});
builder.Services.AddRazorComponents().AddInteractiveServerComponents();
var microsoft365 = ReadMicrosoft365Options(builder.Configuration);
Microsoft365Configuration.Validate(microsoft365);
builder.Services.AddSingleton(microsoft365);
builder.Services.AddSingleton<IntegrationRuntimeState>();
builder.Services.AddSingleton<IntegrationReadinessService>();
builder.Services.AddHttpContextAccessor();
builder.Services.AddCascadingAuthenticationState();
if (microsoft365.Mode == IntegrationMode.Microsoft365ReadOnly)
{
    builder.Services
        .AddAuthentication(OpenIdConnectDefaults.AuthenticationScheme)
        .AddMicrosoftIdentityWebApp(builder.Configuration.GetSection("Microsoft365"), OpenIdConnectDefaults.AuthenticationScheme, CookieAuthenticationDefaults.AuthenticationScheme)
        .EnableTokenAcquisitionToCallDownstreamApi(["Place.Read.All", "Calendars.ReadBasic"])
        .AddInMemoryTokenCaches();
    builder.Services.AddAuthorization(options =>
    {
        options.FallbackPolicy = new AuthorizationPolicyBuilder()
            .RequireAuthenticatedUser()
            .RequireClaim("tid", microsoft365.TenantId)
            .RequireRole("PlaceHub.OfficeManager", "PlaceHub.LocationManager", "PlaceHub.SystemAdministrator")
            .Build();
    });
    builder.Services.Configure<CookieAuthenticationOptions>(CookieAuthenticationDefaults.AuthenticationScheme, options =>
    {
        options.Cookie.HttpOnly = true;
        options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
        options.Cookie.SameSite = SameSiteMode.Lax;
        options.SlidingExpiration = false;
        options.ExpireTimeSpan = TimeSpan.FromHours(8);
    });
    builder.Services.Configure<OpenIdConnectOptions>(OpenIdConnectDefaults.AuthenticationScheme, options =>
    {
        options.ResponseType = OpenIdConnectResponseType.Code;
        options.UsePkce = true;
        options.SaveTokens = false;
        options.GetClaimsFromUserInfoEndpoint = false;
        options.TokenValidationParameters.ValidateIssuer = true;
        options.TokenValidationParameters.ValidIssuer = $"https://login.microsoftonline.com/{microsoft365.TenantId}/v2.0";
        options.TokenValidationParameters.ValidateAudience = true;
        options.TokenValidationParameters.ValidAudience = microsoft365.ClientId;
        options.TokenValidationParameters.NameClaimType = "name";
        options.TokenValidationParameters.RoleClaimType = "roles";
    });
    builder.Services.AddScoped<IDelegatedTokenProvider, MicrosoftIdentityDelegatedTokenProvider>();
}
else
{
    builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme).AddCookie(CookieAuthenticationDefaults.AuthenticationScheme);
    builder.Services.AddAuthorization();
    builder.Services.AddSingleton<IDelegatedTokenProvider, UnavailableDelegatedTokenProvider>();
}
builder.Services.AddScoped<CurrentActorContext>();
if (microsoft365.Mode == IntegrationMode.OfflineMock)
{
    builder.Services.AddSingleton<IPlacesReader, OfflinePlacesReader>();
    builder.Services.AddSingleton<IAvailabilityReader, OfflineAvailabilityReader>();
}
else
{
    builder.Services.AddHttpClient<IPlacesReader, GraphPlacesReader>(client => client.BaseAddress = new("https://graph.microsoft.com/v1.0/"));
    builder.Services.AddHttpClient<IAvailabilityReader, GraphAvailabilityReader>(client => client.BaseAddress = new("https://graph.microsoft.com/v1.0/"));
}
builder.Services.AddSingleton<IAdministrationRepository, InMemoryAdministrationRepository>();
if (microsoft365.Mode == IntegrationMode.OfflineMock) builder.Services.AddSingleton<IProvisioningWorker, OfflineMockProvisioningWorker>();
else builder.Services.AddSingleton<IProvisioningWorker, DisabledProvisioningWorker>();
builder.Services.AddSingleton<AdministrationService>();
var app = builder.Build();
if (!app.Environment.IsDevelopment()) app.UseExceptionHandler("/Error", createScopeForErrors: true);
app.UseAuthentication();
app.UseAuthorization();
app.UseAntiforgery();
app.MapStaticAssets();
var components = app.MapRazorComponents<App>().AddInteractiveServerRenderMode();
if (microsoft365.Mode == IntegrationMode.Microsoft365ReadOnly) components.RequireAuthorization();
if (microsoft365.Mode == IntegrationMode.Microsoft365ReadOnly)
{
    app.MapGet("/auth/signin", async context => await context.ChallengeAsync(OpenIdConnectDefaults.AuthenticationScheme, new AuthenticationProperties { RedirectUri = "/" })).AllowAnonymous();
    app.MapGet("/auth/signout", async context => await context.SignOutAsync(OpenIdConnectDefaults.AuthenticationScheme, new AuthenticationProperties { RedirectUri = "/" }));
}
app.MapGet("/health/live", () => Results.Ok(new { status = "healthy", mode = microsoft365.Mode.ToString() })).AllowAnonymous();
app.Run();

static Microsoft365Options ReadMicrosoft365Options(IConfiguration configuration)
{
    var mode = Enum.TryParse<IntegrationMode>(configuration["Microsoft365:Mode"], true, out var parsed) ? parsed : IntegrationMode.OfflineMock;
    return new()
    {
        Mode = mode,
        TenantId = configuration["Microsoft365:TenantId"] ?? "",
        ClientId = configuration["Microsoft365:ClientId"] ?? "",
        CallbackPath = configuration["Microsoft365:CallbackPath"] ?? "/signin-oidc",
        SignedOutCallbackPath = configuration["Microsoft365:SignedOutCallbackPath"] ?? "/signout-callback-oidc",
        ClientCertificatePath = configuration["Microsoft365:ClientCertificatePath"] ?? "",
        CredentialProvider = configuration["Microsoft365:CredentialProvider"] ?? "None",
        AllowSyntheticData = bool.TryParse(configuration["Microsoft365:AllowSyntheticData"], out var synthetic) && synthetic
    };
}
