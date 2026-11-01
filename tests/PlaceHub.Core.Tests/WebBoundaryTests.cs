using System.Reflection;
using PlaceHub.Core;
using Xunit;

namespace PlaceHub.Core.Tests;

public sealed class WebBoundaryTests
{
    private static readonly Type[] Privileged = [typeof(IPlacesWriteClient), typeof(GraphPlacesWriteClient), typeof(IWorkerTokenProvider), typeof(UnavailableWorkerTokenProvider), typeof(PlacesProvisioningWorker), typeof(IBootstrapGuard)];

    private static IEnumerable<Type> WebTypes() => typeof(PlaceHub.Web.CurrentActorContext).Assembly.GetTypes();

    [Fact]
    public void WebAssemblyNeverReferencesPrivilegedPlacesWriteTypes()
    {
        const BindingFlags all = BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.DeclaredOnly;
        foreach (var type in WebTypes())
        {
            var used = type.GetFields(all).Select(f => f.FieldType)
                .Concat(type.GetProperties(all).Select(p => p.PropertyType))
                .Concat(type.GetConstructors(all).SelectMany(c => c.GetParameters().Select(p => p.ParameterType)))
                .Concat(type.GetMethods(all).SelectMany(m => m.GetParameters().Select(p => p.ParameterType).Append(m.ReturnType)));
            foreach (var u in used) Assert.DoesNotContain(Privileged, p => p.IsAssignableFrom(u) || u.IsAssignableFrom(p) && u != typeof(object));
        }
    }

    [Fact]
    public void WebSourceNeverMentionsPrivilegedWriteComponents()
    {
        var root = AppContext.BaseDirectory; while (root is not null && !File.Exists(Path.Combine(root, "PlaceHub.slnx"))) root = Path.GetDirectoryName(root);
        Assert.NotNull(root);
        var web = Path.Combine(root!, "src", "PlaceHub.Web");
        var text = string.Join("\n", Directory.EnumerateFiles(web, "*.*", SearchOption.AllDirectories).Where(f => !f.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}") && !f.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}") && (f.EndsWith(".cs") || f.EndsWith(".razor") || f.EndsWith(".json"))).Select(File.ReadAllText));
        foreach (var forbidden in new[] { "IPlacesWriteClient", "GraphPlacesWriteClient", "IWorkerTokenProvider", "PlacesProvisioningWorker", "Place.ReadWrite", "Exchange.ManageAsApp", "KeyVault", "client_secret" })
            Assert.DoesNotContain(forbidden, text);
    }

    [Fact]
    public void WebDelegatedScopesStayReadOnly()
    {
        var root = AppContext.BaseDirectory; while (root is not null && !File.Exists(Path.Combine(root, "PlaceHub.slnx"))) root = Path.GetDirectoryName(root);
        var program = File.ReadAllText(Path.Combine(root!, "src", "PlaceHub.Web", "Program.cs"));
        Assert.Contains("[\"Place.Read.All\", \"Calendars.ReadBasic\"]", program);
        Assert.DoesNotContain("ReadWrite", program);
    }

    [Fact]
    public void AnUnapprovedPlacesWorkerIsNotRegisteredInTheWebContainer()
    {
        var root = AppContext.BaseDirectory; while (root is not null && !File.Exists(Path.Combine(root, "PlaceHub.slnx"))) root = Path.GetDirectoryName(root);
        var program = File.ReadAllText(Path.Combine(root!, "src", "PlaceHub.Web", "Program.cs"));
        Assert.Contains("DisabledProvisioningWorker", program);
    }
}
