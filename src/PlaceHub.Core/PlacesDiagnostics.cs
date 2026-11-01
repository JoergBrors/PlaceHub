namespace PlaceHub.Core;

/// <summary>Classified result of a bounded, single-pass Places inventory diagnosis. PendingPropagation is only reported when a prior report supplies evidence.</summary>
public enum PlacesDiagnosticOutcome { VerifiedEmpty, ResourceFound, PermissionDenied, TenantMismatch, ApiUnsupported, PendingPropagation, InconsistentDirectoryState, Unknown }

public sealed record PlacesTypeDiagnostic(PlaceType Type, int Listed, int Authorized);

public sealed record PlacesDiagnosticReport(
    DateTimeOffset At, PlacesDiagnosticOutcome Outcome, string Source, IReadOnlyList<PlacesTypeDiagnostic> Types,
    int AssignedLocations, int AssignedLocationsResolved, int DirectLookups, IReadOnlyList<string> Warnings, string? FailureCode = null);

/// <summary>Never exposes names, identifiers or details of resources outside the caller's authorization: only counts and states.</summary>
public sealed class PlacesDiagnosticsService(IPlacesReader reader)
{
    public async Task<PlacesDiagnosticReport> RunAsync(ReadAuthorizationContext authorization, CancellationToken cancellationToken, PlacesDiagnosticReport? previous = null)
    {
        var now = DateTimeOffset.UtcNow;
        try { return Classify(await reader.ReadHierarchyAsync(authorization, cancellationToken), authorization.LocationIds, now, previous); }
        catch (IntegrationException ex) { return Failure(ex.Code, now); }
    }

    public static PlacesDiagnosticReport Failure(string code, DateTimeOffset at)
    {
        var outcome = code switch
        {
            "GRAPH_PERMISSION_DENIED" or "EFFECTIVE_SCOPE_MISSING" or "CONSENT_OR_LOGIN_REQUIRED" or "DELEGATED_SCOPE_MISSING" or "TOKEN_ACQUISITION_FAILED" => PlacesDiagnosticOutcome.PermissionDenied,
            "TENANT_MISMATCH" or "TOKEN_TENANT_MISMATCH" => PlacesDiagnosticOutcome.TenantMismatch,
            "TENANT_CAPABILITY_UNAVAILABLE" => PlacesDiagnosticOutcome.ApiUnsupported,
            _ => PlacesDiagnosticOutcome.Unknown
        };
        return new(at, outcome, "Microsoft365ReadOnly", [], 0, 0, 0, [$"Der Lesezugriff ist fehlgeschlagen ({code}); es liegen keine Inventardaten vor."], code);
    }

    public static PlacesDiagnosticReport Classify(PlacesSnapshot snapshot, IReadOnlySet<string> locations, DateTimeOffset at, PlacesDiagnosticReport? previous = null)
    {
        var warnings = new List<string>();
        var counts = snapshot.ListCounts;
        if (counts is null) warnings.Add("Die Listenzahlen sind nicht verfügbar; eine Aussage über Verzug oder Leere ist nicht möglich.");
        var types = Enum.GetValues<PlaceType>().Select(t => new PlacesTypeDiagnostic(t, counts?.GetValueOrDefault(t.ToString()) ?? 0, snapshot.Places.Count(p => p.Type == t))).ToArray();
        int Listed(PlaceType t) => types.First(x => x.Type == t).Listed;
        var resolved = locations.Count(l => snapshot.Places.Any(p => p.Type == PlaceType.Building && (string.Equals(p.Id, l, StringComparison.OrdinalIgnoreCase) || string.Equals(p.StablePlaceId, l, StringComparison.OrdinalIgnoreCase))));
        var totalListed = types.Sum(t => t.Listed);

        PlacesDiagnosticOutcome outcome;
        if (counts is null) outcome = PlacesDiagnosticOutcome.Unknown;
        else if (resolved > 0 && Listed(PlaceType.Building) == 0)
        {
            outcome = PlacesDiagnosticOutcome.InconsistentDirectoryState;
            warnings.Add("Ein zugewiesenes Gebäude ist per ID lesbar, erscheint aber nicht in der Gebäudeliste. Die Ursache ist nicht belegt; ein Index- oder Synchronisationsverzug ist möglich, aber unbewiesen.");
        }
        else if (resolved > 0) outcome = PlacesDiagnosticOutcome.ResourceFound;
        else if (totalListed == 0) { outcome = PlacesDiagnosticOutcome.VerifiedEmpty; warnings.Add("Alle Typlisten sind für diese Identität leer und kein zugewiesener Standort ist auflösbar. Das gilt nur für diese Identität und diesen Zeitpunkt."); }
        else { outcome = PlacesDiagnosticOutcome.ResourceFound; warnings.Add("Es existieren Ressourcen, aber keine ist für Ihre Standortzuweisung sichtbar."); }

        if (locations.Count > 0 && resolved < locations.Count && counts is not null) warnings.Add($"{locations.Count - resolved} zugewiesene(r) Standort(e) konnte(n) nicht als Gebäude aufgelöst werden.");
        if (Listed(PlaceType.Room) > 0 && types.First(t => t.Type == PlaceType.Room).Authorized == 0) warnings.Add("Räume sind vorhanden, aber keinem zugewiesenen Gebäude zugeordnet oder ohne Hierarchie (nicht sichtbar nach Autorisierung).");
        if (Listed(PlaceType.Workspace) + Listed(PlaceType.Desk) > 0 && Listed(PlaceType.Section) == 0 && counts is not null) warnings.Add("Workspaces oder Desks ohne gelistete Abschnitte: mögliche verwaiste Objekte oder verzögerte Typlisten.");
        // Only report propagation when a previous pass observed the inconsistent state and the lists now agree.
        if (previous?.Outcome == PlacesDiagnosticOutcome.InconsistentDirectoryState && outcome == PlacesDiagnosticOutcome.ResourceFound)
        { outcome = PlacesDiagnosticOutcome.PendingPropagation; warnings.Add($"Beim vorherigen Lauf ({previous.At:u}) fehlte das Gebäude in der Liste, jetzt ist es gelistet: das ist ein Hinweis auf nachgezogene Listen, kein Beweis für die Dauer."); }
        return new(at, outcome, snapshot.DataSource, types, locations.Count, resolved, snapshot.DirectLookups, warnings);
    }
}
