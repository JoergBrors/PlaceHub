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
builder.Services.AddSingleton<IAdministrationRepository, InMemoryAdministrationRepository>();
builder.Services.AddSingleton<IProvisioningWorker, OfflineMockProvisioningWorker>();
builder.Services.AddSingleton<AdministrationService>();
builder.Services.AddScoped<DemoActorContext>();
var app = builder.Build();
if (!app.Environment.IsDevelopment()) app.UseExceptionHandler("/Error", createScopeForErrors: true);
app.UseAntiforgery();
app.MapStaticAssets();
app.MapRazorComponents<App>().AddInteractiveServerRenderMode();
app.MapGet("/health/live", () => Results.Ok(new { status = "healthy", mode = "offline-mock" }));
app.Run();

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
