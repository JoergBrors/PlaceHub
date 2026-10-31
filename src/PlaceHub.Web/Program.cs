using PlaceHub.Core;
using PlaceHub.Web;
using PlaceHub.Web.Components;

var builder = WebApplication.CreateBuilder(args);
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
