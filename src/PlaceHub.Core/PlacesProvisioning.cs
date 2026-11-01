using System.Net;
using System.Text;
using System.Text.Json;

namespace PlaceHub.Core;

/// <summary>Typed, allowlisted Microsoft Places write payload. Nothing here is a free-form Graph request.</summary>
public sealed record PlacesWriteSpec(
    PlaceType Kind, string DisplayName, string? ParentPlaceId, IReadOnlyList<string>? Tags = null,
    string? TargetPlaceId = null, string? BootstrapEntryId = null)
{
    public static PlaceType? RequiredParent(PlaceType kind) => kind switch
    {
        PlaceType.Floor => PlaceType.Building,
        PlaceType.Section => PlaceType.Floor,
        PlaceType.Workspace or PlaceType.Desk => PlaceType.Section,
        _ => null
    };

    public static string ODataType(PlaceType kind) => kind switch
    {
        PlaceType.Building => "microsoft.graph.building",
        PlaceType.Floor => "microsoft.graph.floor",
        PlaceType.Section => "microsoft.graph.section",
        PlaceType.Workspace => "microsoft.graph.workspace",
        PlaceType.Desk => "microsoft.graph.desk",
        _ => throw new ValidationException("PLACE_KIND_NOT_ALLOWED")
    };

    internal static bool IsSafeId(string? value) => !string.IsNullOrWhiteSpace(value) && value.Length <= 128 && value.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_' or '.');
    private static bool IsSafeText(string value, int max) => value.Length is >= 1 && value.Length <= max && value.Trim() == value && value.All(c => char.IsLetterOrDigit(c) || c is ' ' or '-' or '_' or '.' or '/' or '(' or ')');

    public void Validate(OperationKind operation)
    {
        if (Kind is not (PlaceType.Building or PlaceType.Floor or PlaceType.Section or PlaceType.Workspace or PlaceType.Desk)) throw new ValidationException("PLACE_KIND_NOT_ALLOWED");
        if (operation is not (OperationKind.Create or OperationKind.Update)) throw new ValidationException("PLACES_OPERATION_NOT_ALLOWED");
        if (!IsSafeText(DisplayName ?? "", 128)) throw new ValidationException("PLACE_DISPLAY_NAME_INVALID");
        if (Tags is { Count: > 10 } || (Tags ?? []).Any(t => !IsSafeText(t, 64))) throw new ValidationException("PLACE_TAGS_INVALID");
        if (BootstrapEntryId is not null && (Kind != PlaceType.Building || operation != OperationKind.Create || !IsSafeId(BootstrapEntryId))) throw new ValidationException("BOOTSTRAP_SPEC_INVALID");
        if (operation == OperationKind.Create)
        {
            if (TargetPlaceId is not null) throw new ValidationException("PLACE_TARGET_NOT_ALLOWED_ON_CREATE");
            var parent = RequiredParent(Kind);
            if (parent is null && ParentPlaceId is not null) throw new ValidationException("PLACE_PARENT_NOT_ALLOWED");
            if (parent is not null && !IsSafeId(ParentPlaceId)) throw new ValidationException("PLACE_PARENT_REQUIRED");
        }
        else
        {
            if (!IsSafeId(TargetPlaceId)) throw new ValidationException("PLACE_TARGET_REQUIRED");
            if (ParentPlaceId is not null) throw new ValidationException("PLACE_REPARENT_NOT_SUPPORTED");
        }
    }
}

public sealed record PlacesInventory(int Buildings, int Floors, int Sections, int Workspaces, int Desks, int Rooms, int RoomLists, int ExchangeResourceMailboxes, bool Complete, DateTimeOffset ReadAt)
{
    public bool BuildingsEmptyAndVerified => Complete && Buildings == 0;
}

public interface IPlacesInventoryReader { Task<PlacesInventory> ReadAsync(CancellationToken cancellationToken); }

public interface IBootstrapGuard
{
    /// <summary>Atomically begins the single allowed bootstrap; false if one is running, completed or ambiguous.</summary>
    bool TryBegin(string entryId);
    void Complete(string entryId, bool definitive);
}

public sealed class InMemoryBootstrapGuard : IBootstrapGuard
{
    private readonly object gate = new(); private string? used;
    public bool TryBegin(string entryId) { lock (gate) { if (used is not null) return false; used = entryId; return true; } }
    public void Complete(string entryId, bool definitive) { lock (gate) { if (!definitive && used == entryId) used = entryId; } }
}

public sealed record BootstrapManifestEntry(string Id, string DisplayName);
public sealed record BootstrapManifest(string Environment, string Status, IReadOnlyList<BootstrapManifestEntry> Entries)
{
    public const string ApprovedStatus = "APPROVED_BY_PROJECT_OWNER";
    public static BootstrapManifest Load(string json) =>
        JsonSerializer.Deserialize<BootstrapManifest>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? throw new ValidationException("BOOTSTRAP_MANIFEST_INVALID");
    public BootstrapManifestEntry Resolve(string entryId, string displayName)
    {
        if (!string.Equals(Status, ApprovedStatus, StringComparison.Ordinal)) throw new ValidationException("BOOTSTRAP_MANIFEST_NOT_APPROVED");
        var entry = Entries.FirstOrDefault(e => string.Equals(e.Id, entryId, StringComparison.Ordinal)) ?? throw new ValidationException("BOOTSTRAP_ENTRY_UNKNOWN");
        if (!string.Equals(entry.DisplayName, displayName, StringComparison.Ordinal)) throw new ValidationException("BOOTSTRAP_NAME_NOT_IN_MANIFEST");
        return entry;
    }
}

public sealed record PlacesWriteOptions
{
    /// <summary>Master switch. The worker refuses to run while false.</summary>
    public bool Enabled { get; init; }
    public string Environment { get; init; } = "";
    /// <summary>Workspace and Reservable/DropIn desk creation creates mailboxes implicitly and needs its own approval.</summary>
    public bool MailboxCreationApproved { get; init; }
    public int ReadBackAttempts { get; init; } = 3;
    public TimeSpan ReadBackDelay { get; init; } = TimeSpan.FromSeconds(5);
}

public interface IWorkerTokenProvider { Task<string> GetAppTokenAsync(CancellationToken cancellationToken); }
public sealed class UnavailableWorkerTokenProvider : IWorkerTokenProvider
{
    public Task<string> GetAppTokenAsync(CancellationToken cancellationToken) => throw new IntegrationConfigurationException("WORKER_CREDENTIAL_UNAVAILABLE");
}

/// <summary>The create outcome cannot be determined (timeout, 5xx after send); never retried automatically.</summary>
public sealed class AmbiguousOutcomeException(string code) : IntegrationException(code);

public interface IPlacesWriteClient
{
    Task<IReadOnlyList<PlaceRecord>> ListAsync(PlaceType type, CancellationToken cancellationToken);
    Task<PlaceRecord?> GetAsync(string graphId, CancellationToken cancellationToken);
    Task<PlaceRecord> CreateAsync(PlacesWriteSpec spec, string parentGraphId, CancellationToken cancellationToken);
    Task UpdateAsync(string graphId, PlacesWriteSpec spec, CancellationToken cancellationToken);
}

public sealed class GraphPlacesWriteClient(HttpClient http, IWorkerTokenProvider tokens, Func<TimeSpan, CancellationToken, Task>? delay = null) : IPlacesWriteClient
{
    private readonly Func<TimeSpan, CancellationToken, Task> wait = delay ?? Task.Delay;

    public async Task<IReadOnlyList<PlaceRecord>> ListAsync(PlaceType type, CancellationToken cancellationToken)
    {
        var token = await tokens.GetAppTokenAsync(cancellationToken);
        var records = new List<PlaceRecord>(); Uri? next = new($"places/{PlacesWriteSpec.ODataType(type)}?$select=id,placeId,parentId,displayName,tags", UriKind.Relative); var pages = 0;
        while (next is not null)
        {
            if (++pages > 25) throw new IntegrationException("GRAPH_PAGE_LIMIT_EXCEEDED");
            using var doc = await SendAsync(HttpMethod.Get, next, token, null, retry: true, cancellationToken) ?? throw new IntegrationException("GRAPH_RESPONSE_INVALID");
            foreach (var item in doc.RootElement.GetProperty("value").EnumerateArray()) records.Add(Map(item, type));
            next = doc.RootElement.TryGetProperty("@odata.nextLink", out var link) ? ValidateNext(link.GetString()) : null;
        }
        return records;
    }

    public async Task<PlaceRecord?> GetAsync(string graphId, CancellationToken cancellationToken)
    {
        if (!PlacesWriteSpec.IsSafeId(graphId)) throw new ValidationException("PLACE_ID_INVALID");
        var token = await tokens.GetAppTokenAsync(cancellationToken);
        try
        {
            using var doc = await SendAsync(HttpMethod.Get, new($"places/{Uri.EscapeDataString(graphId)}", UriKind.Relative), token, null, retry: true, cancellationToken);
            return doc is null ? null : Map(doc.RootElement, TypeOf(doc.RootElement));
        }
        catch (IntegrationException ex) when (ex.Code == "PLACE_NOT_FOUND") { return null; }
    }

    public async Task<PlaceRecord> CreateAsync(PlacesWriteSpec spec, string parentGraphId, CancellationToken cancellationToken)
    {
        var token = await tokens.GetAppTokenAsync(cancellationToken);
        var body = new Dictionary<string, object?> { ["@odata.type"] = PlacesWriteSpec.ODataType(spec.Kind), ["displayName"] = spec.DisplayName };
        if (PlacesWriteSpec.RequiredParent(spec.Kind) is not null) body["parentId"] = parentGraphId;
        if (spec.Tags is { Count: > 0 }) body["tags"] = spec.Tags;
        using var doc = await SendAsync(HttpMethod.Post, new("places", UriKind.Relative), token, JsonSerializer.Serialize(body), retry: false, cancellationToken) ?? throw new AmbiguousOutcomeException("CREATE_RESPONSE_EMPTY");
        return Map(doc.RootElement, spec.Kind);
    }

    public async Task UpdateAsync(string graphId, PlacesWriteSpec spec, CancellationToken cancellationToken)
    {
        if (!PlacesWriteSpec.IsSafeId(graphId)) throw new ValidationException("PLACE_ID_INVALID");
        var token = await tokens.GetAppTokenAsync(cancellationToken);
        var body = new Dictionary<string, object?> { ["@odata.type"] = PlacesWriteSpec.ODataType(spec.Kind), ["displayName"] = spec.DisplayName };
        if (spec.Tags is not null) body["tags"] = spec.Tags;
        using var doc = await SendAsync(HttpMethod.Patch, new($"places/{Uri.EscapeDataString(graphId)}", UriKind.Relative), token, JsonSerializer.Serialize(body), retry: false, cancellationToken);
    }

    private async Task<JsonDocument?> SendAsync(HttpMethod method, Uri uri, string token, string? json, bool retry, CancellationToken cancellationToken)
    {
        for (var attempt = 1; ; attempt++)
        {
            using var request = new HttpRequestMessage(method, uri) { Content = json is null ? null : new StringContent(json, Encoding.UTF8, "application/json") };
            request.Headers.Authorization = new("Bearer", token);
            HttpResponseMessage response;
            try { response = await http.SendAsync(request, cancellationToken); }
            catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException && !cancellationToken.IsCancellationRequested)
            { throw method == HttpMethod.Get ? new IntegrationException("GRAPH_UNAVAILABLE") : new AmbiguousOutcomeException("WRITE_OUTCOME_UNKNOWN"); }
            using (response)
            {
                if (response.IsSuccessStatusCode)
                {
                    if (response.StatusCode == HttpStatusCode.NoContent) return null;
                    return await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(cancellationToken), cancellationToken: cancellationToken);
                }
                var status = (int)response.StatusCode;
                // 429 means the request was rejected before processing, so a bounded retry cannot duplicate a write.
                if (status == 429 && attempt < 3) { await wait(Min(response.Headers.RetryAfter?.Delta ?? TimeSpan.FromMilliseconds(100 * attempt), TimeSpan.FromSeconds(10)), cancellationToken); continue; }
                if (status == 503 && retry && attempt < 3) { await wait(TimeSpan.FromMilliseconds(100 * attempt), cancellationToken); continue; }
                throw status switch
                {
                    401 or 403 => new IntegrationException("GRAPH_WRITE_PERMISSION_DENIED"),
                    404 => new IntegrationException("PLACE_NOT_FOUND"),
                    409 => new IntegrationException("PLACE_CONFLICT"),
                    429 => new IntegrationException("GRAPH_THROTTLED"),
                    >= 500 when method != HttpMethod.Get => new AmbiguousOutcomeException("WRITE_OUTCOME_UNKNOWN"),
                    >= 500 => new IntegrationException("GRAPH_UNAVAILABLE"),
                    _ => new IntegrationException("GRAPH_REQUEST_REJECTED")
                };
            }
        }
    }

    private static TimeSpan Min(TimeSpan a, TimeSpan b) => a < b ? a : b;
    private static Uri? ValidateNext(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps || !uri.Host.Equals("graph.microsoft.com", StringComparison.OrdinalIgnoreCase) || !uri.AbsolutePath.StartsWith("/v1.0/places/", StringComparison.Ordinal)) throw new IntegrationException("GRAPH_NEXT_LINK_REJECTED");
        return uri;
    }

    private static PlaceType TypeOf(JsonElement e)
    {
        var odata = e.TryGetProperty("@odata.type", out var t) ? t.GetString() ?? "" : "";
        foreach (var kind in new[] { PlaceType.Building, PlaceType.Floor, PlaceType.Section, PlaceType.Workspace, PlaceType.Desk }) if (odata.EndsWith(PlacesWriteSpec.ODataType(kind), StringComparison.OrdinalIgnoreCase)) return kind;
        throw new IntegrationException("PLACE_TYPE_UNSUPPORTED");
    }

    private static string? Str(JsonElement e, string name) => e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
    private static PlaceRecord Map(JsonElement e, PlaceType type)
    {
        var id = Str(e, "id") ?? Str(e, "placeId") ?? throw new IntegrationException("GRAPH_RESPONSE_INVALID");
        DateTimeOffset? updated = DateTimeOffset.TryParse(Str(e, "lastUpdatedTime"), out var u) ? u : null;
        return new(id, Str(e, "parentId"), type, Str(e, "displayName") ?? "", null, Str(e, "emailAddress"), null, "Microsoft365Places", DateTimeOffset.UtcNow, Str(e, "placeId"), updated);
    }
}

/// <summary>
/// Executes approved Places requests. Refuses to run unless explicitly enabled, revalidates the approval itself,
/// never retries an ambiguous create, and verifies every write by reading it back.
/// </summary>
public sealed class PlacesProvisioningWorker(
    IPlacesWriteClient client, IPlacesInventoryReader inventory, IBootstrapGuard guard, BootstrapManifest manifest,
    PlacesWriteOptions options, Func<TimeSpan, CancellationToken, Task>? delay = null) : IProvisioningWorker
{
    private readonly Func<TimeSpan, CancellationToken, Task> wait = delay ?? Task.Delay;

    public async Task<ProvisioningResult> ExecuteAsync(AdministrationRequest request, CancellationToken cancellationToken)
    {
        request.VerifyApprovalIntegrity();
        if (!options.Enabled) throw new WorkflowException("PLACES_WRITE_NOT_ACTIVATED");
        var spec = request.Specification.Places;
        if (spec is null) return new(RequestState.Failed, "OPERATION_NOT_ALLOWLISTED");
        var operation = request.Specification.Operation;
        try { spec.Validate(operation); }
        catch (ValidationException ex) { return new(RequestState.Failed, ex.Code); }
        if (operation == OperationKind.Create && spec.Kind is PlaceType.Workspace or PlaceType.Desk && !options.MailboxCreationApproved)
            return new(RequestState.Failed, "MAILBOX_CREATE_NOT_APPROVED");

        var bootstrap = spec.BootstrapEntryId is not null;
        if (bootstrap)
        {
            var gate = await CheckBootstrapAsync(spec, request, cancellationToken);
            if (gate is not null) return gate;
        }
        try
        {
            var result = operation == OperationKind.Create ? await CreateAsync(spec, cancellationToken) : await UpdateAsync(spec, cancellationToken);
            if (bootstrap) guard.Complete(spec.BootstrapEntryId!, result.State is RequestState.Succeeded or RequestState.Failed);
            return result;
        }
        catch (AmbiguousOutcomeException ex)
        {
            if (bootstrap) guard.Complete(spec.BootstrapEntryId!, definitive: false);
            return new(RequestState.RequiresReconciliation, ex.Code);
        }
        catch (IntegrationException ex)
        {
            if (bootstrap) guard.Complete(spec.BootstrapEntryId!, definitive: false);
            return new(RequestState.Failed, ex.Code);
        }
    }

    private async Task<ProvisioningResult?> CheckBootstrapAsync(PlacesWriteSpec spec, AdministrationRequest request, CancellationToken cancellationToken)
    {
        if (!string.Equals(options.Environment, "development", StringComparison.OrdinalIgnoreCase) || !string.Equals(manifest.Environment, "development", StringComparison.OrdinalIgnoreCase))
            return new(RequestState.Failed, "BOOTSTRAP_DEVELOPMENT_ONLY");
        try { manifest.Resolve(spec.BootstrapEntryId!, spec.DisplayName); }
        catch (ValidationException ex) { return new(RequestState.Failed, ex.Code); }
        PlacesInventory current;
        try { current = await inventory.ReadAsync(cancellationToken); }
        catch (IntegrationException ex) { return new(RequestState.Failed, ex.Code); }
        if (!current.Complete) return new(RequestState.Failed, "BOOTSTRAP_INVENTORY_INCOMPLETE");
        if (!current.BuildingsEmptyAndVerified) return new(RequestState.Failed, "BOOTSTRAP_BUILDINGS_EXIST");
        if (!guard.TryBegin(spec.BootstrapEntryId!)) return new(RequestState.Failed, "BOOTSTRAP_ALREADY_USED_OR_RUNNING");
        return null;
    }

    private static bool SameParent(PlaceRecord record, PlaceRecord parent) =>
        string.Equals(record.ParentId, parent.Id, StringComparison.OrdinalIgnoreCase) ||
        (parent.StablePlaceId is not null && string.Equals(record.ParentId, parent.StablePlaceId, StringComparison.OrdinalIgnoreCase));

    private async Task<ProvisioningResult> CreateAsync(PlacesWriteSpec spec, CancellationToken cancellationToken)
    {
        PlaceRecord? parent = null;
        if (PlacesWriteSpec.RequiredParent(spec.Kind) is { } parentType)
        {
            parent = (await client.ListAsync(parentType, cancellationToken))
                .FirstOrDefault(p => string.Equals(p.StablePlaceId ?? p.Id, spec.ParentPlaceId, StringComparison.OrdinalIgnoreCase) || string.Equals(p.Id, spec.ParentPlaceId, StringComparison.OrdinalIgnoreCase));
            if (parent is null) return new(RequestState.Failed, "PARENT_NOT_FOUND_OR_WRONG_TYPE");
        }
        var existing = (await client.ListAsync(spec.Kind, cancellationToken))
            .Where(p => string.Equals(p.DisplayName, spec.DisplayName, StringComparison.OrdinalIgnoreCase) && (parent is null || SameParent(p, parent))).ToArray();
        if (existing.Length > 0) return new(RequestState.RequiresReconciliation, "DUPLICATE_EXISTS", existing[0].StablePlaceId ?? existing[0].Id);

        var created = await client.CreateAsync(spec, parent?.Id ?? "", cancellationToken);
        return await VerifyAsync(created, spec, parent, cancellationToken);
    }

    private async Task<ProvisioningResult> VerifyAsync(PlaceRecord created, PlacesWriteSpec spec, PlaceRecord? parent, CancellationToken cancellationToken)
    {
        var placeId = created.StablePlaceId ?? created.Id;
        for (var attempt = 1; attempt <= Math.Max(1, options.ReadBackAttempts); attempt++)
        {
            var read = await client.GetAsync(created.Id, cancellationToken);
            if (read is not null)
            {
                var ok = read.Type == spec.Kind && string.Equals(read.DisplayName, spec.DisplayName, StringComparison.Ordinal) && (parent is null || SameParent(read, parent)) && (read.StablePlaceId ?? read.Id) == placeId;
                return ok ? new(RequestState.Succeeded, "PLACE_CREATED_VERIFIED", placeId) : new(RequestState.RequiresReconciliation, "READ_AFTER_WRITE_MISMATCH", placeId);
            }
            if (attempt < options.ReadBackAttempts) await wait(options.ReadBackDelay, cancellationToken);
        }
        return new(RequestState.PendingPropagation, "PLACE_PENDING_PROPAGATION", placeId);
    }

    private async Task<ProvisioningResult> UpdateAsync(PlacesWriteSpec spec, CancellationToken cancellationToken)
    {
        var target = await client.GetAsync(spec.TargetPlaceId!, cancellationToken);
        if (target is null) return new(RequestState.Failed, "PLACE_NOT_FOUND");
        if (target.Type != spec.Kind) return new(RequestState.Failed, "PLACE_TYPE_MISMATCH");
        await client.UpdateAsync(target.Id, spec, cancellationToken);
        var read = await client.GetAsync(target.Id, cancellationToken);
        if (read is null) return new(RequestState.PendingPropagation, "PLACE_PENDING_PROPAGATION", target.StablePlaceId ?? target.Id);
        return string.Equals(read.DisplayName, spec.DisplayName, StringComparison.Ordinal)
            ? new(RequestState.Succeeded, "PLACE_UPDATED_VERIFIED", read.StablePlaceId ?? read.Id)
            : new(RequestState.PendingPropagation, "PLACE_UPDATE_PENDING_PROPAGATION", read.StablePlaceId ?? read.Id);
    }
}
