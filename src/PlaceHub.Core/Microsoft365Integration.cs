using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace PlaceHub.Core;

public enum IntegrationMode { OfflineMock, Microsoft365ReadOnly }
public enum PlaceType { Building, Floor, Section, Workspace, Desk }
public enum AvailabilityState { Free, Busy, Tentative, OutOfOffice, Unknown }

public sealed record Microsoft365Options
{
    public IntegrationMode Mode { get; init; } = IntegrationMode.OfflineMock;
    public string TenantId { get; init; } = "";
    public string ClientId { get; init; } = "";
    public string CallbackPath { get; init; } = "/signin-oidc";
    public string SignedOutCallbackPath { get; init; } = "/signout-callback-oidc";
    public string CredentialProvider { get; init; } = "None";
    public bool PermissionsApproved { get; init; }
    public bool ConsentVerified { get; init; }
    public bool TenantCapabilityVerified { get; init; }
    public bool AllowSyntheticData { get; init; }
}

public static class Microsoft365Configuration
{
    public static void Validate(Microsoft365Options options)
    {
        if (options.Mode == IntegrationMode.OfflineMock)
        {
            if (!options.AllowSyntheticData) throw new IntegrationConfigurationException("SYNTHETIC_PROFILE_NOT_EXPLICITLY_ENABLED");
            if (!string.IsNullOrWhiteSpace(options.TenantId) || !string.IsNullOrWhiteSpace(options.ClientId) || options.CredentialProvider != "None" || options.PermissionsApproved || options.ConsentVerified || options.TenantCapabilityVerified)
                throw new IntegrationConfigurationException("MOCK_LIVE_CONFIGURATION_CONFLICT");
            return;
        }
        if (!Guid.TryParse(options.TenantId, out _) || !Guid.TryParse(options.ClientId, out _)) throw new IntegrationConfigurationException("ENTRA_IDENTIFIERS_INVALID");
        if (options.CallbackPath != "/signin-oidc" || options.SignedOutCallbackPath != "/signout-callback-oidc") throw new IntegrationConfigurationException("OIDC_CALLBACK_INVALID");
        if (options.CredentialProvider == "None") throw new IntegrationConfigurationException("CONFIDENTIAL_CLIENT_CREDENTIAL_UNAVAILABLE");
        if (!options.PermissionsApproved) throw new IntegrationConfigurationException("PERMISSIONS_NOT_APPROVED");
        if (!options.ConsentVerified) throw new IntegrationConfigurationException("CONSENT_NOT_VERIFIED");
        if (!options.TenantCapabilityVerified) throw new IntegrationConfigurationException("TENANT_CAPABILITY_NOT_VERIFIED");
    }
}

public sealed record IntegrationReadinessItem(string Name, string State, string Code);
public sealed class IntegrationReadinessService(Microsoft365Options options)
{
    public IntegrationMode Mode => options.Mode;
    public IReadOnlyList<IntegrationReadinessItem> GetStatus() =>
    [
        new("Entra-Konfiguration", HasIdentifiers ? "Konfiguriert" : "Nicht konfiguriert", HasIdentifiers ? "ENTRA_CONFIGURATION_PRESENT" : "ENTRA_CONFIGURATION_MISSING"),
        new("Confidential-Client-Credential", options.CredentialProvider != "None" ? "Konfiguriert" : "Nicht genehmigt", options.CredentialProvider != "None" ? "CREDENTIAL_PROVIDER_PRESENT" : "CREDENTIAL_PROVIDER_UNAVAILABLE"),
        new("Place.Read.All", options.PermissionsApproved ? "Genehmigt" : "Nicht genehmigt", options.PermissionsApproved ? "PERMISSION_APPROVED" : "PERMISSION_NOT_APPROVED"),
        new("Admin Consent", options.ConsentVerified ? "Consent verifiziert" : "Nicht verifiziert", options.ConsentVerified ? "CONSENT_VERIFIED" : "CONSENT_NOT_VERIFIED"),
        new("Places-Tenantfähigkeit", options.TenantCapabilityVerified ? "Verifiziert" : "Nicht verifiziert", options.TenantCapabilityVerified ? "TENANT_CAPABILITY_VERIFIED" : "TENANT_CAPABILITY_UNKNOWN"),
        new("Live-Netzwerkzugriff", options.Mode == IntegrationMode.Microsoft365ReadOnly ? "Read-only angefordert" : "Gesperrt", options.Mode == IntegrationMode.Microsoft365ReadOnly ? "READ_ONLY_MODE" : "OFFLINE_NETWORK_BLOCKED")
    ];
    private bool HasIdentifiers => Guid.TryParse(options.TenantId, out _) && Guid.TryParse(options.ClientId, out _);
}

public sealed record ReadAuthorizationContext(
    string TenantId, string SubjectId, PlaceHubRole? Role, IReadOnlySet<string> LocationIds,
    IReadOnlySet<string> DelegatedScopes, IReadOnlySet<string> ResourceMailboxes, bool IsSyntheticIdentity)
{
    public void DemandTenant(string expectedTenantId)
    {
        if (IsSyntheticIdentity) throw new IntegrationAuthorizationException("MOCK_IDENTITY_DENIED_FROM_LIVE_MODE");
        if (!Guid.TryParse(TenantId, out _) || !TenantId.Equals(expectedTenantId, StringComparison.OrdinalIgnoreCase)) throw new IntegrationAuthorizationException("TENANT_MISMATCH");
    }
    public void Demand(string scope, string locationId)
    {
        if (IsSyntheticIdentity) throw new IntegrationAuthorizationException("MOCK_IDENTITY_DENIED_FROM_LIVE_MODE");
        if (string.IsNullOrWhiteSpace(TenantId) || string.IsNullOrWhiteSpace(SubjectId)) throw new IntegrationAuthorizationException("INVALID_IDENTITY");
        if (Role is not (PlaceHubRole.OfficeManager or PlaceHubRole.LocationManager or PlaceHubRole.SystemAdministrator)) throw new IntegrationAuthorizationException("APPLICATION_ROLE_MISSING");
        if (!LocationIds.Contains(locationId)) throw new IntegrationAuthorizationException("LOCATION_OUT_OF_SCOPE");
        if (!DelegatedScopes.Contains(scope)) throw new IntegrationAuthorizationException("DELEGATED_SCOPE_MISSING");
    }
}

public sealed record PlaceRecord(string Id, string? ParentId, PlaceType Type, string DisplayName, int? Capacity, string? EmailAddress, string? OperationalState, string DataSource, DateTimeOffset ReadAt);
public sealed record PlacesSnapshot(IReadOnlyList<PlaceRecord> Places, string DataSource, DateTimeOffset ReadAt);
public sealed record AvailabilityRequest(string LocationId, IReadOnlyList<string> ResourceMailboxes, DateTimeOffset Start, DateTimeOffset End, string WindowsTimeZone);
public sealed record ResourceAvailability(string ResourceMailbox, AvailabilityState State, DateTimeOffset Start, DateTimeOffset End, string DataSource);

public interface IPlacesReader { Task<PlacesSnapshot> ReadHierarchyAsync(ReadAuthorizationContext authorization, CancellationToken cancellationToken); }
public interface IAvailabilityReader { Task<IReadOnlyList<ResourceAvailability>> ReadAsync(AvailabilityRequest request, ReadAuthorizationContext authorization, CancellationToken cancellationToken); }
public interface IDelegatedTokenProvider { Task<string> GetTokenAsync(IReadOnlySet<string> scopes, CancellationToken cancellationToken); }

public sealed class UnavailableDelegatedTokenProvider : IDelegatedTokenProvider
{
    public Task<string> GetTokenAsync(IReadOnlySet<string> scopes, CancellationToken cancellationToken) => throw new IntegrationConfigurationException("CONFIDENTIAL_CLIENT_CREDENTIAL_UNAVAILABLE");
}

public sealed class OfflinePlacesReader : IPlacesReader
{
    public Task<PlacesSnapshot> ReadHierarchyAsync(ReadAuthorizationContext authorization, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var now = DateTimeOffset.UtcNow;
        var items = SyntheticResources.DeskPools.Where(x => authorization.LocationIds.Contains(x.LocationId)).SelectMany(x => new PlaceRecord[]
        {
            new(x.LocationId, null, PlaceType.Building, x.Building, null, null, "Synthetic", "OfflineMock", now),
            new($"{x.LocationId}-floor-{x.Floor}", x.LocationId, PlaceType.Floor, x.Floor, null, null, "Synthetic", "OfflineMock", now),
            new($"{x.LocationId}-section-{x.Section}", $"{x.LocationId}-floor-{x.Floor}", PlaceType.Section, x.Section, null, null, "Synthetic", "OfflineMock", now),
            new(x.Id, $"{x.LocationId}-section-{x.Section}", PlaceType.Workspace, x.Name, x.Capacity, x.MailboxAlias, x.Status, "OfflineMock", now)
        }).GroupBy(x => x.Id, StringComparer.Ordinal).Select(x => x.First()).ToArray();
        return Task.FromResult(new PlacesSnapshot(items, "OfflineMock", now));
    }
}

public sealed class OfflineAvailabilityReader : IAvailabilityReader
{
    public Task<IReadOnlyList<ResourceAvailability>> ReadAsync(AvailabilityRequest request, ReadAuthorizationContext authorization, CancellationToken cancellationToken)
    {
        ValidateAvailabilityRequest(request); cancellationToken.ThrowIfCancellationRequested();
        IReadOnlyList<ResourceAvailability> result = request.ResourceMailboxes.Select((x, i) => new ResourceAvailability(x, i % 3 == 0 ? AvailabilityState.Free : i % 3 == 1 ? AvailabilityState.Busy : AvailabilityState.Unknown, request.Start, request.End, "OfflineMock")).ToArray();
        return Task.FromResult(result);
    }

    internal static void ValidateAvailabilityRequest(AvailabilityRequest request)
    {
        if (request.End <= request.Start || request.End - request.Start > TimeSpan.FromDays(1)) throw new ValidationException("AVAILABILITY_INTERVAL_INVALID");
        if (request.ResourceMailboxes.Count is < 1 or > 20) throw new ValidationException("RESOURCE_MAILBOX_COUNT_INVALID");
        if (string.IsNullOrWhiteSpace(request.WindowsTimeZone)) throw new ValidationException("TIME_ZONE_REQUIRED");
        if (request.ResourceMailboxes.Any(x => string.IsNullOrWhiteSpace(x) || !x.Contains('@') || x.Length > 254)) throw new ValidationException("RESOURCE_MAILBOX_INVALID");
    }
}

public sealed class GraphPlacesReader(HttpClient httpClient, IDelegatedTokenProvider tokenProvider, Microsoft365Options options) : IPlacesReader
{
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };
    private static readonly IReadOnlySet<string> Scopes = new HashSet<string>(StringComparer.Ordinal) { "Place.Read.All" };
    private static readonly (PlaceType Type, string ODataType, string Select)[] Types =
    [
        (PlaceType.Building,"microsoft.graph.building","id,placeId,displayName"),
        (PlaceType.Floor,"microsoft.graph.floor","id,placeId,parentId,displayName"),
        (PlaceType.Section,"microsoft.graph.section","id,placeId,parentId,displayName"),
        (PlaceType.Workspace,"microsoft.graph.workspace","id,placeId,parentId,displayName,capacity,emailAddress"),
        (PlaceType.Desk,"microsoft.graph.desk","id,placeId,parentId,displayName")
    ];

    public async Task<PlacesSnapshot> ReadHierarchyAsync(ReadAuthorizationContext authorization, CancellationToken cancellationToken)
    {
        authorization.DemandTenant(options.TenantId);
        if (authorization.LocationIds.Count == 0) throw new IntegrationAuthorizationException("LOCATION_ASSIGNMENT_MISSING");
        foreach (var location in authorization.LocationIds) authorization.Demand("Place.Read.All", location);
        var token = await tokenProvider.GetTokenAsync(Scopes, cancellationToken);
        var now = DateTimeOffset.UtcNow; var records = new List<PlaceRecord>();
        foreach (var (type, odata, select) in Types)
        {
            var uri = new Uri($"places/{odata}?$select={select}", UriKind.Relative);
            await foreach (var item in ReadPagesAsync(uri, token, cancellationToken))
            {
                var id = item.PlaceId ?? item.Id;
                if (string.IsNullOrWhiteSpace(id)) continue;
                records.Add(new(id, item.ParentId, type, item.DisplayName ?? "Unbekannt", item.Capacity, item.EmailAddress ?? item.MailboxDetails?.EmailAddress, null, "Microsoft365ReadOnly", now));
            }
        }
        var allowed = FilterAuthorizedHierarchy(records, authorization.LocationIds);
        return new(allowed, "Microsoft365ReadOnly", now);
    }

    private static IReadOnlyList<PlaceRecord> FilterAuthorizedHierarchy(IReadOnlyList<PlaceRecord> records, IReadOnlySet<string> locations)
    {
        var allowedIds = new HashSet<string>(locations, StringComparer.OrdinalIgnoreCase); var changed = true;
        while (changed) { changed = false; foreach (var record in records) if (record.ParentId is not null && allowedIds.Contains(record.ParentId) && allowedIds.Add(record.Id)) changed = true; }
        return records.Where(x => allowedIds.Contains(x.Id)).ToArray();
    }

    private async IAsyncEnumerable<GraphPlace> ReadPagesAsync(Uri initial, string token, [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken cancellationToken)
    {
        Uri? next = initial; var pages = 0;
        while (next is not null)
        {
            if (++pages > 25) throw new IntegrationException("GRAPH_PAGE_LIMIT_EXCEEDED");
            using var request = new HttpRequestMessage(HttpMethod.Get, next); request.Headers.Authorization = new("Bearer", token);
            using var response = await SendWithRetryAsync(request, cancellationToken);
            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            var page = await JsonSerializer.DeserializeAsync<GraphPage>(stream, JsonOptions, cancellationToken) ?? throw new IntegrationException("GRAPH_RESPONSE_INVALID");
            foreach (var value in page.Value ?? []) yield return value;
            next = ValidateNextLink(page.NextLink);
        }
    }

    private async Task<HttpResponseMessage> SendWithRetryAsync(HttpRequestMessage original, CancellationToken cancellationToken)
    {
        for (var attempt = 1; attempt <= 3; attempt++)
        {
            using var request = new HttpRequestMessage(original.Method, original.RequestUri); request.Headers.Authorization = original.Headers.Authorization;
            var response = await httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            if (response.IsSuccessStatusCode) return response;
            if (response.StatusCode is not (HttpStatusCode.TooManyRequests or HttpStatusCode.ServiceUnavailable) || attempt == 3)
            { var status = (int)response.StatusCode; response.Dispose(); throw new IntegrationException(status == 403 ? "GRAPH_PERMISSION_DENIED" : status == 404 ? "TENANT_CAPABILITY_UNAVAILABLE" : status == 429 ? "GRAPH_THROTTLED" : status == 503 ? "GRAPH_UNAVAILABLE" : "GRAPH_REQUEST_FAILED"); }
            var delay = response.Headers.RetryAfter?.Delta ?? TimeSpan.FromMilliseconds(100 * attempt); response.Dispose();
            await Task.Delay(delay > TimeSpan.FromSeconds(10) ? TimeSpan.FromSeconds(10) : delay, cancellationToken);
        }
        throw new IntegrationException("GRAPH_REQUEST_FAILED");
    }

    private static Uri? ValidateNextLink(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps || !uri.Host.Equals("graph.microsoft.com", StringComparison.OrdinalIgnoreCase) || !uri.AbsolutePath.StartsWith("/v1.0/places/", StringComparison.Ordinal)) throw new IntegrationException("GRAPH_NEXT_LINK_REJECTED");
        return uri;
    }

    private sealed record GraphPage([property:JsonPropertyName("value")] GraphPlace[]? Value, [property:JsonPropertyName("@odata.nextLink")] string? NextLink);
    private sealed record GraphPlace(string? Id, string? PlaceId, string? ParentId, string? DisplayName, int? Capacity, string? EmailAddress, MailboxDetails? MailboxDetails);
    private sealed record MailboxDetails(string? EmailAddress);
}

public sealed class GraphAvailabilityReader(HttpClient httpClient, IDelegatedTokenProvider tokenProvider, Microsoft365Options options) : IAvailabilityReader
{
    private static readonly IReadOnlySet<string> Scopes = new HashSet<string>(StringComparer.Ordinal) { "Calendars.ReadBasic" };
    public async Task<IReadOnlyList<ResourceAvailability>> ReadAsync(AvailabilityRequest request, ReadAuthorizationContext authorization, CancellationToken cancellationToken)
    {
        OfflineAvailabilityReader.ValidateAvailabilityRequest(request); authorization.DemandTenant(options.TenantId); authorization.Demand("Calendars.ReadBasic", request.LocationId);
        if (request.ResourceMailboxes.Any(x => !authorization.ResourceMailboxes.Contains(x))) throw new IntegrationAuthorizationException("RESOURCE_MAILBOX_OUT_OF_SCOPE");
        var token = await tokenProvider.GetTokenAsync(Scopes, cancellationToken);
        using var message = new HttpRequestMessage(HttpMethod.Post, "me/calendar/getSchedule"); message.Headers.Authorization = new("Bearer", token); message.Headers.TryAddWithoutValidation("Prefer", $"outlook.timezone=\"{request.WindowsTimeZone}\"");
        message.Content = JsonContent.Create(new { schedules=request.ResourceMailboxes, startTime=new { dateTime=request.Start.ToString("yyyy-MM-ddTHH:mm:ss"), timeZone=request.WindowsTimeZone }, endTime=new { dateTime=request.End.ToString("yyyy-MM-ddTHH:mm:ss"), timeZone=request.WindowsTimeZone }, availabilityViewInterval=30 });
        using var response = await httpClient.SendAsync(message, cancellationToken);
        if (!response.IsSuccessStatusCode) throw new IntegrationException(response.StatusCode == HttpStatusCode.Forbidden ? "GRAPH_PERMISSION_DENIED" : "GRAPH_AVAILABILITY_FAILED");
        var payload = await response.Content.ReadFromJsonAsync<ScheduleResponse>(cancellationToken: cancellationToken) ?? throw new IntegrationException("GRAPH_RESPONSE_INVALID");
        return (payload.Value ?? []).Select(x => new ResourceAvailability(x.ScheduleId ?? "unknown", FromAvailabilityView(x.AvailabilityView), request.Start, request.End, "Microsoft365ReadOnly")).ToArray();
    }
    private static AvailabilityState FromAvailabilityView(string? view) => string.IsNullOrWhiteSpace(view) ? AvailabilityState.Unknown : view.All(x => x == '0') ? AvailabilityState.Free : view.Any(x => x is '2' or '3') ? AvailabilityState.Busy : view.Any(x => x == '1') ? AvailabilityState.Tentative : AvailabilityState.Unknown;
    private sealed record ScheduleResponse([property:JsonPropertyName("value")] ScheduleEntry[]? Value);
    private sealed record ScheduleEntry(string? ScheduleId, string? AvailabilityView);
}

public class IntegrationException(string code) : Exception(code) { public string Code { get; } = code; }
public sealed class IntegrationAuthorizationException(string code) : IntegrationException(code);
public sealed class IntegrationConfigurationException(string code) : IntegrationException(code);
