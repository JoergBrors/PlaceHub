using PlaceHub.Core;
using Xunit;

namespace PlaceHub.Core.Tests;

public sealed class PlacesDiagnosticsTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-11-01T12:00:00Z");
    private static PlaceRecord Place(PlaceType type, string id, string? parent = null, string? stable = null) => new(id, parent, type, "name", null, null, null, "test", Now, stable);
    private static PlacesSnapshot Snapshot(IEnumerable<PlaceRecord> places, Dictionary<string, int>? counts, int lookups = 0) => new(places.ToArray(), "Microsoft365ReadOnly", Now, counts, lookups);
    private static IReadOnlySet<string> Locations(params string[] ids) => new HashSet<string>(ids, StringComparer.OrdinalIgnoreCase);

    [Fact]
    public void AllEmptyListsAndNoResolvableLocationIsVerifiedEmptyWithACaveat()
    {
        var report = PlacesDiagnosticsService.Classify(Snapshot([], new()), Locations("b1"), Now);
        Assert.Equal(PlacesDiagnosticOutcome.VerifiedEmpty, report.Outcome);
        Assert.Contains(report.Warnings, w => w.Contains("nur für diese Identität"));
    }

    [Fact]
    public void BuildingReadableByIdButMissingFromTheListIsAnInconsistentDirectoryStateAndNeverClaimsAPropagationDelay()
    {
        var report = PlacesDiagnosticsService.Classify(Snapshot([Place(PlaceType.Building, "id", null, "b1")], new() { ["Room"] = 1 }, 1), Locations("b1"), Now);
        Assert.Equal(PlacesDiagnosticOutcome.InconsistentDirectoryState, report.Outcome);
        Assert.Equal(1, report.AssignedLocationsResolved);
        Assert.Contains(report.Warnings, w => w.Contains("unbewiesen"));
        Assert.DoesNotContain(report.Outcome.ToString(), "PendingPropagation");
    }

    [Fact]
    public void ListedAndResolvedBuildingIsResourceFound()
    {
        var report = PlacesDiagnosticsService.Classify(Snapshot([Place(PlaceType.Building, "b1")], new() { ["Building"] = 1 }), Locations("b1"), Now);
        Assert.Equal(PlacesDiagnosticOutcome.ResourceFound, report.Outcome);
    }

    [Fact]
    public void PropagationIsOnlyReportedWithEvidenceFromAPreviousInconsistentRun()
    {
        var inconsistent = PlacesDiagnosticsService.Classify(Snapshot([Place(PlaceType.Building, "b1")], new(), 1), Locations("b1"), Now);
        var listed = Snapshot([Place(PlaceType.Building, "b1")], new() { ["Building"] = 1 });
        Assert.Equal(PlacesDiagnosticOutcome.ResourceFound, PlacesDiagnosticsService.Classify(listed, Locations("b1"), Now).Outcome);
        var later = PlacesDiagnosticsService.Classify(listed, Locations("b1"), Now.AddHours(1), inconsistent);
        Assert.Equal(PlacesDiagnosticOutcome.PendingPropagation, later.Outcome);
        Assert.Contains(later.Warnings, w => w.Contains("kein Beweis für die Dauer"));
    }

    [Fact]
    public void ExistingResourcesOutsideTheAssignmentAreReportedWithoutDetails()
    {
        var report = PlacesDiagnosticsService.Classify(Snapshot([], new() { ["Building"] = 3, ["Room"] = 2 }), Locations("mine"), Now);
        Assert.Equal(PlacesDiagnosticOutcome.ResourceFound, report.Outcome);
        Assert.Equal(3, report.Types.Single(t => t.Type == PlaceType.Building).Listed);
        Assert.Equal(0, report.Types.Single(t => t.Type == PlaceType.Building).Authorized);
        Assert.Contains(report.Warnings, w => w.Contains("nicht sichtbar"));
        Assert.DoesNotContain(report.Warnings, w => w.Contains("mine"));
    }

    [Fact]
    public void RoomWithoutAHierarchyAndOrphanedWorkspacesAreFlagged()
    {
        var report = PlacesDiagnosticsService.Classify(Snapshot([], new() { ["Room"] = 1, ["Workspace"] = 1 }), Locations("b1"), Now);
        Assert.Contains(report.Warnings, w => w.Contains("ohne Hierarchie"));
        Assert.Contains(report.Warnings, w => w.Contains("verwaiste"));
    }

    [Fact]
    public void MissingListCountsYieldUnknownNeverEmpty()
    {
        var report = PlacesDiagnosticsService.Classify(Snapshot([], null), Locations("b1"), Now);
        Assert.Equal(PlacesDiagnosticOutcome.Unknown, report.Outcome);
    }

    [Theory]
    [InlineData("GRAPH_PERMISSION_DENIED", PlacesDiagnosticOutcome.PermissionDenied)]
    [InlineData("EFFECTIVE_SCOPE_MISSING", PlacesDiagnosticOutcome.PermissionDenied)]
    [InlineData("CONSENT_OR_LOGIN_REQUIRED", PlacesDiagnosticOutcome.PermissionDenied)]
    [InlineData("TENANT_MISMATCH", PlacesDiagnosticOutcome.TenantMismatch)]
    [InlineData("TOKEN_TENANT_MISMATCH", PlacesDiagnosticOutcome.TenantMismatch)]
    [InlineData("TENANT_CAPABILITY_UNAVAILABLE", PlacesDiagnosticOutcome.ApiUnsupported)]
    [InlineData("GRAPH_UNAVAILABLE", PlacesDiagnosticOutcome.Unknown)]
    public void FailureCodesMapToTheDocumentedOutcomes(string code, PlacesDiagnosticOutcome expected)
    {
        var report = PlacesDiagnosticsService.Failure(code, Now);
        Assert.Equal(expected, report.Outcome); Assert.Equal(code, report.FailureCode); Assert.Empty(report.Types);
    }

    [Fact]
    public async Task RunTranslatesReaderExceptionsAndIsASingleBoundedPass()
    {
        var reader = new CountingReader(new IntegrationException("GRAPH_PERMISSION_DENIED"));
        var report = await new PlacesDiagnosticsService(reader).RunAsync(Auth(), default);
        Assert.Equal(PlacesDiagnosticOutcome.PermissionDenied, report.Outcome);
        Assert.Equal(1, reader.Calls);
    }

    [Fact]
    public async Task RunUsesTheReaderOnceOnSuccess()
    {
        var reader = new CountingReader(null) { Result = Snapshot([Place(PlaceType.Building, "b1")], new() { ["Building"] = 1 }) };
        var report = await new PlacesDiagnosticsService(reader).RunAsync(Auth(), default);
        Assert.Equal(PlacesDiagnosticOutcome.ResourceFound, report.Outcome); Assert.Equal(1, reader.Calls);
    }

    private static ReadAuthorizationContext Auth() => new("11111111-1111-1111-1111-111111111111", "s", PlaceHubRole.OfficeManager, Locations("b1"), new HashSet<string> { "Place.Read.All" }, new HashSet<string>(), false);

    private sealed class CountingReader(Exception? failure) : IPlacesReader
    {
        public int Calls; public PlacesSnapshot Result = new([], "x", DateTimeOffset.UtcNow, new Dictionary<string, int>());
        public Task<PlacesSnapshot> ReadHierarchyAsync(ReadAuthorizationContext authorization, CancellationToken cancellationToken) { Calls++; return failure is null ? Task.FromResult(Result) : throw failure; }
    }
}
