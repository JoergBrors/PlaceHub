using System.Collections.Concurrent;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace PlaceHub.Core;

/// <summary>
/// Exchange stays authoritative. A created event is only Pending; Accepted exists only after the resource mailbox's own
/// response was read back. Unknown and RequiresReconciliation are explicit states, never silently turned into success.
/// </summary>
public enum ReservationState { Pending, Accepted, Declined, Cancelled, Unknown, RequiresReconciliation }

public sealed record ParkingReservation(
    Guid Id, string IdempotencyKey, Guid SpaceId, string LocationId, string MailboxAddress, string OrganizerSubject,
    DateTimeOffset Start, DateTimeOffset End, string TimeZone, ReservationState State, string OutcomeCode,
    string? GraphEventId, DateTimeOffset UpdatedAt, DateTimeOffset? ConfirmedAt);

public sealed record BookingOptions
{
    /// <summary>Master switch for booking writes. Stays false until ADR-007 booking semantics are accepted.</summary>
    public bool WritesEnabled { get; init; }
    /// <summary>Delegated Calendars.ReadWrite must be consented and allowlisted for the web application (separate approval).</summary>
    public bool DelegatedWriteScopeApproved { get; init; }
    public IReadOnlyList<string> AllowedTimeZones { get; init; } = ["W. Europe Standard Time", "UTC"];
    public TimeSpan MaxDuration { get; init; } = TimeSpan.FromHours(24);
    public TimeSpan MaxLeadTime { get; init; } = TimeSpan.FromDays(14);
}

public sealed record BookingEventSpec(string MailboxAddress, string LocationDisplayName, DateTimeOffset Start, DateTimeOffset End, string TimeZone, string TransactionId);
public sealed record BookingEventStatus(string EventId, bool IsCancelled, string? ResourceResponse);

public interface IBookingGraphClient
{
    Task<string> CreateEventAsync(BookingEventSpec spec, CancellationToken cancellationToken);
    Task<BookingEventStatus?> GetEventAsync(string eventId, string resourceMailbox, CancellationToken cancellationToken);
    Task CancelEventAsync(string eventId, CancellationToken cancellationToken);
}

public interface IReservationRepository
{
    IReadOnlyCollection<ParkingReservation> GetAll();
    ParkingReservation? Find(Guid id);
    ParkingReservation? FindByKey(string idempotencyKey);
    bool TryAdd(ParkingReservation reservation);
    void Replace(ParkingReservation reservation);
}

/// <summary>Development-only, non-persistent. Persistence of real reservations needs the ADR-010 amendment.</summary>
public sealed class InMemoryReservationRepository : IReservationRepository
{
    private readonly object gate = new(); private readonly Dictionary<Guid, ParkingReservation> items = new(); private readonly Dictionary<string, Guid> keys = new(StringComparer.Ordinal);
    public IReadOnlyCollection<ParkingReservation> GetAll() { lock (gate) return items.Values.OrderBy(x => x.Start).ToArray(); }
    public ParkingReservation? Find(Guid id) { lock (gate) return items.GetValueOrDefault(id); }
    public ParkingReservation? FindByKey(string key) { lock (gate) return keys.TryGetValue(key, out var id) ? items[id] : null; }
    public bool TryAdd(ParkingReservation r) { lock (gate) { if (!keys.TryAdd(r.IdempotencyKey, r.Id)) return false; items[r.Id] = r; return true; } }
    public void Replace(ParkingReservation r) { lock (gate) if (items.ContainsKey(r.Id)) items[r.Id] = r; }
}

public sealed class GraphBookingClient(HttpClient http, IDelegatedTokenProvider tokens, Func<TimeSpan, CancellationToken, Task>? delay = null) : IBookingGraphClient
{
    private static readonly IReadOnlySet<string> Scopes = new HashSet<string>(StringComparer.Ordinal) { "Calendars.ReadWrite" };
    private static readonly Regex EventId = new(@"^[A-Za-z0-9_=-]{8,400}$", RegexOptions.Compiled | RegexOptions.CultureInvariant);
    private readonly Func<TimeSpan, CancellationToken, Task> wait = delay ?? Task.Delay;

    public async Task<string> CreateEventAsync(BookingEventSpec spec, CancellationToken cancellationToken)
    {
        if (!ExchangeSpec.IsValidAddress(spec.MailboxAddress)) throw new ValidationException("MAILBOX_ADDRESS_INVALID");
        var body = JsonSerializer.Serialize(new
        {
            subject = "Parkplatz-Reservierung",
            start = new { dateTime = spec.Start.ToString("yyyy-MM-ddTHH:mm:ss"), timeZone = spec.TimeZone },
            end = new { dateTime = spec.End.ToString("yyyy-MM-ddTHH:mm:ss"), timeZone = spec.TimeZone },
            attendees = new[] { new { emailAddress = new { address = spec.MailboxAddress }, type = "resource" } },
            locations = new[] { new { displayName = spec.LocationDisplayName } },
            isReminderOn = false,
            transactionId = spec.TransactionId
        });
        using var doc = await SendAsync(HttpMethod.Post, "me/events", body, retryThrottle: true, cancellationToken) ?? throw new AmbiguousOutcomeException("CREATE_RESPONSE_EMPTY");
        return doc.RootElement.TryGetProperty("id", out var id) && id.GetString() is { } value && EventId.IsMatch(value) ? value : throw new AmbiguousOutcomeException("CREATE_RESPONSE_INVALID");
    }

    public async Task<BookingEventStatus?> GetEventAsync(string eventId, string resourceMailbox, CancellationToken cancellationToken)
    {
        if (!EventId.IsMatch(eventId)) throw new ValidationException("EVENT_ID_INVALID");
        try
        {
            using var doc = await SendAsync(HttpMethod.Get, $"me/events/{Uri.EscapeDataString(eventId)}?$select=id,isCancelled,attendees", null, retryThrottle: true, cancellationToken);
            if (doc is null) return null;
            var cancelled = doc.RootElement.TryGetProperty("isCancelled", out var c) && c.ValueKind == JsonValueKind.True;
            string? response = null;
            if (doc.RootElement.TryGetProperty("attendees", out var attendees) && attendees.ValueKind == JsonValueKind.Array)
                foreach (var a in attendees.EnumerateArray())
                    if (a.TryGetProperty("emailAddress", out var e) && e.TryGetProperty("address", out var addr) && string.Equals(addr.GetString(), resourceMailbox, StringComparison.OrdinalIgnoreCase)
                        && a.TryGetProperty("status", out var status) && status.TryGetProperty("response", out var r)) response = r.GetString();
            return new(eventId, cancelled, response);
        }
        catch (IntegrationException ex) when (ex.Code == "EVENT_NOT_FOUND") { return null; }
    }

    public async Task CancelEventAsync(string eventId, CancellationToken cancellationToken)
    {
        if (!EventId.IsMatch(eventId)) throw new ValidationException("EVENT_ID_INVALID");
        using var _ = await SendAsync(HttpMethod.Post, $"me/events/{Uri.EscapeDataString(eventId)}/cancel", JsonSerializer.Serialize(new { comment = "Reservierung storniert." }), retryThrottle: true, cancellationToken);
    }

    private async Task<JsonDocument?> SendAsync(HttpMethod method, string relative, string? json, bool retryThrottle, CancellationToken cancellationToken)
    {
        var token = await tokens.GetTokenAsync(Scopes, cancellationToken);
        for (var attempt = 1; ; attempt++)
        {
            using var request = new HttpRequestMessage(method, new Uri(relative, UriKind.Relative)) { Content = json is null ? null : new StringContent(json, Encoding.UTF8, "application/json") };
            request.Headers.Authorization = new("Bearer", token);
            HttpResponseMessage response;
            try { response = await http.SendAsync(request, cancellationToken); }
            catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException && !cancellationToken.IsCancellationRequested)
            { throw method == HttpMethod.Get ? new IntegrationException("GRAPH_UNAVAILABLE") : new AmbiguousOutcomeException("WRITE_OUTCOME_UNKNOWN"); }
            using (response)
            {
                if (response.IsSuccessStatusCode)
                    return response.StatusCode is HttpStatusCode.NoContent or HttpStatusCode.Accepted && (response.Content.Headers.ContentLength ?? 0) == 0 ? null : await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(cancellationToken), cancellationToken: cancellationToken);
                var status = (int)response.StatusCode;
                if (status == 429 && retryThrottle && attempt < 3) { await wait(TimeSpan.FromMilliseconds(100 * attempt), cancellationToken); continue; }
                throw status switch
                {
                    401 or 403 => new IntegrationException("BOOKING_PERMISSION_DENIED"),
                    404 => new IntegrationException("EVENT_NOT_FOUND"),
                    409 => new IntegrationException("BOOKING_CONFLICT"),
                    429 => new IntegrationException("GRAPH_THROTTLED"),
                    >= 500 when method != HttpMethod.Get => new AmbiguousOutcomeException("WRITE_OUTCOME_UNKNOWN"),
                    >= 500 => new IntegrationException("GRAPH_UNAVAILABLE"),
                    _ => new IntegrationException("GRAPH_REQUEST_REJECTED")
                };
            }
        }
    }
}

public sealed class ParkingReservationService(
    IReservationRepository repository, IBookingGraphClient graph, IAvailabilityReader availability, ParkingService parking, BookingOptions options, TimeProvider? clock = null)
{
    private readonly TimeProvider time = clock ?? TimeProvider.System;

    public IReadOnlyCollection<ParkingReservation> List(Actor actor) => repository.GetAll().Where(r => actor.LocationIds.Contains(r.LocationId)).ToArray();

    public ParkingReservation Get(Guid id, Actor actor)
    {
        var r = repository.Find(id) ?? throw new WorkflowException("RESERVATION_NOT_FOUND");
        if (!actor.LocationIds.Contains(r.LocationId)) throw new AuthorizationException("LOCATION_OUT_OF_SCOPE");
        return r;
    }

    public async Task<ParkingReservation> RequestAsync(Actor actor, ReadAuthorizationContext authorization, Guid spaceId, DateTimeOffset start, DateTimeOffset end, string timeZone, string idempotencyKey, CancellationToken cancellationToken)
    {
        if (!options.WritesEnabled || !options.DelegatedWriteScopeApproved) throw new WorkflowException("BOOKING_WRITES_NOT_ACTIVATED");
        if (string.IsNullOrWhiteSpace(idempotencyKey) || idempotencyKey.Length > 64) throw new ValidationException("IDEMPOTENCY_KEY_REQUIRED");
        if (string.IsNullOrWhiteSpace(actor.Id)) throw new AuthorizationException("IDENTITY_UNKNOWN");
        if (repository.FindByKey(idempotencyKey) is { } existing) return existing.OrganizerSubject == actor.Id ? existing : throw new AuthorizationException("IDEMPOTENCY_KEY_IN_USE");
        var space = parking.Get(spaceId, actor);
        if (space.Status != ParkingStatus.Active) throw new WorkflowException("PARKING_SPACE_NOT_VERIFIED");
        var now = time.GetUtcNow();
        if (!options.AllowedTimeZones.Contains(timeZone, StringComparer.Ordinal)) throw new ValidationException("TIME_ZONE_NOT_ALLOWED");
        if (end <= start || end - start > options.MaxDuration) throw new ValidationException("BOOKING_INTERVAL_INVALID");
        if (start < now || start - now > options.MaxLeadTime) throw new ValidationException("BOOKING_START_OUT_OF_WINDOW");
        if (repository.GetAll().Any(r => r.SpaceId == spaceId && r.State is ReservationState.Pending or ReservationState.Accepted or ReservationState.Unknown or ReservationState.RequiresReconciliation && start < r.End && r.Start < end))
            throw new WorkflowException("BOOKING_CONFLICT");

        // Advisory pre-check only: Exchange decides. A busy or unknown answer blocks, a free answer is no guarantee.
        var states = await availability.ReadAsync(new(space.LocationId, [space.MailboxAddress], start, end, timeZone), authorization, cancellationToken);
        var state = states.FirstOrDefault(s => string.Equals(s.ResourceMailbox, space.MailboxAddress, StringComparison.OrdinalIgnoreCase))?.State ?? AvailabilityState.Unknown;
        if (state is AvailabilityState.Busy or AvailabilityState.OutOfOffice) throw new WorkflowException("BOOKING_CONFLICT");
        if (state is AvailabilityState.Unknown) throw new WorkflowException("AVAILABILITY_UNKNOWN");

        var reservation = new ParkingReservation(Guid.NewGuid(), idempotencyKey, spaceId, space.LocationId, space.MailboxAddress, actor.Id, start, end, timeZone, ReservationState.Pending, "REQUEST_SUBMITTED", null, now, null);
        if (!repository.TryAdd(reservation)) return repository.FindByKey(idempotencyKey)!;
        try
        {
            var eventId = await graph.CreateEventAsync(new(space.MailboxAddress, space.DisplayName, start, end, timeZone, reservation.Id.ToString("N")), cancellationToken);
            return Save(reservation with { GraphEventId = eventId, OutcomeCode = "AWAITING_EXCHANGE_RESPONSE" });
        }
        catch (AmbiguousOutcomeException ex) { return Save(reservation with { State = ReservationState.RequiresReconciliation, OutcomeCode = ex.Code }); }
        catch (IntegrationException ex) { return Save(reservation with { State = ReservationState.Unknown, OutcomeCode = ex.Code }); }
    }

    /// <summary>Reads the event back; this is the only place that can produce Accepted or Declined (and also handles external Outlook changes).</summary>
    public async Task<ParkingReservation> RefreshAsync(Guid id, Actor actor, CancellationToken cancellationToken)
    {
        var r = Get(id, actor);
        if (r.GraphEventId is null) return r;
        try
        {
            var status = await graph.GetEventAsync(r.GraphEventId, r.MailboxAddress, cancellationToken);
            if (status is null) return Save(r with { State = ReservationState.Cancelled, OutcomeCode = "EVENT_REMOVED_EXTERNALLY" });
            if (status.IsCancelled) return Save(r with { State = ReservationState.Cancelled, OutcomeCode = "EVENT_CANCELLED" });
            return status.ResourceResponse switch
            {
                "accepted" => Save(r with { State = ReservationState.Accepted, OutcomeCode = "EXCHANGE_ACCEPTED", ConfirmedAt = r.ConfirmedAt ?? time.GetUtcNow() }),
                "declined" => Save(r with { State = ReservationState.Declined, OutcomeCode = "EXCHANGE_DECLINED" }),
                "tentativelyAccepted" or "none" or "notResponded" => Save(r with { State = ReservationState.Pending, OutcomeCode = "AWAITING_EXCHANGE_RESPONSE" }),
                null => Save(r with { State = ReservationState.Unknown, OutcomeCode = "RESOURCE_ATTENDEE_NOT_FOUND" }),
                _ => Save(r with { State = ReservationState.Unknown, OutcomeCode = "RESPONSE_UNRECOGNIZED" })
            };
        }
        catch (IntegrationException ex) { return Save(r with { State = r.State == ReservationState.Accepted ? ReservationState.Accepted : ReservationState.Unknown, OutcomeCode = ex.Code }); }
    }

    public async Task<ParkingReservation> CancelAsync(Guid id, Actor actor, CancellationToken cancellationToken)
    {
        if (!options.WritesEnabled || !options.DelegatedWriteScopeApproved) throw new WorkflowException("BOOKING_WRITES_NOT_ACTIVATED");
        var r = Get(id, actor);
        if (!string.Equals(r.OrganizerSubject, actor.Id, StringComparison.OrdinalIgnoreCase)) throw new AuthorizationException("ONLY_THE_ORGANIZER_MAY_CANCEL");
        if (r.State is ReservationState.Cancelled or ReservationState.Declined) return r;
        if (r.GraphEventId is null) return Save(r with { State = ReservationState.Cancelled, OutcomeCode = "CANCELLED_BEFORE_EVENT" });
        try { await graph.CancelEventAsync(r.GraphEventId, cancellationToken); return Save(r with { State = ReservationState.Cancelled, OutcomeCode = "CANCELLED" }); }
        catch (AmbiguousOutcomeException ex) { return Save(r with { State = ReservationState.RequiresReconciliation, OutcomeCode = ex.Code }); }
        catch (IntegrationException ex) { return Save(r with { OutcomeCode = ex.Code }); }
    }

    private ParkingReservation Save(ParkingReservation r) { var updated = r with { UpdatedAt = time.GetUtcNow() }; repository.Replace(updated); return updated; }
}
