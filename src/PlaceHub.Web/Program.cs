using PlaceHub.Core;
using PlaceHub.Web;
using PlaceHub.Web.Components;
using Microsoft.AspNetCore.Hosting.StaticWebAssets;

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
builder.Services.AddSingleton<IntegrationReadinessService>();
builder.Services.AddSingleton<IDelegatedTokenProvider, UnavailableDelegatedTokenProvider>();
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
builder.Services.AddSingleton<IProvisioningWorker, OfflineMockProvisioningWorker>();
builder.Services.AddSingleton<AdministrationService>();
builder.Services.AddScoped<DemoActorContext>();
var app = builder.Build();
if (!app.Environment.IsDevelopment()) app.UseExceptionHandler("/Error", createScopeForErrors: true);
app.UseAntiforgery();
app.MapStaticAssets();
app.MapRazorComponents<App>().AddInteractiveServerRenderMode();
app.MapGet("/health/live", () => Results.Ok(new { status = "healthy", mode = microsoft365.Mode.ToString() }));
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
        CredentialProvider = configuration["Microsoft365:CredentialProvider"] ?? "None",
        PermissionsApproved = bool.TryParse(configuration["Microsoft365:PermissionsApproved"], out var permissions) && permissions,
        ConsentVerified = bool.TryParse(configuration["Microsoft365:ConsentVerified"], out var consent) && consent,
        TenantCapabilityVerified = bool.TryParse(configuration["Microsoft365:TenantCapabilityVerified"], out var capability) && capability
    };
}

namespace PlaceHub.Web
{
    public sealed class DemoActorContext
    {
        public Actor Current { get; private set; } = new("office.manager@synthetic.invalid", PlaceHubRole.OfficeManager, new HashSet<string> { "BER" });
        public void Select(PlaceHubRole role) => Current = role switch
        {
            PlaceHubRole.SystemAdministrator => new("placehub.admin@synthetic.invalid", role, new HashSet<string> { "BER", "HAM" }),
            PlaceHubRole.LocationManager => new("location.manager@synthetic.invalid", role, new HashSet<string> { "BER" }),
            _ => new("office.manager@synthetic.invalid", role, new HashSet<string> { "BER" })
        };
    }
}
