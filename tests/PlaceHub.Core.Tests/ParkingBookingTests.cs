using System.Net;
using System.Text;
using PlaceHub.Core;
using Xunit;

namespace PlaceHub.Core.Tests;

public sealed class ParkingBookingTests
{
    private const string Mailbox = "ph-park-01@contoso.example";
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-11-02T08:00:00Z");
    private static Actor User(string id = "user-1", string location = "BER") => new(id, PlaceHubRole.OfficeManager, new HashSet<string> { location });
    private static ReadAuthorizationContext Auth(Actor a) => new("11111111-1111-1111-1111-111111111111", a.Id, a.Role, a.LocationIds, new HashSet<string> { "Calendars.ReadBasic" }, new HashSet<string>(StringComparer.OrdinalIgnoreCase) { Mailbox }, false);
    private static BookingOptions Open() => new() { WritesEnabled = true, DelegatedWriteScopeApproved = true };

    private static (ParkingReservationService Service, FakeGraph Graph, FakeAvailability Availability, ParkingService Parking, Guid SpaceId) Setup(BookingOptions? options = null, ParkingStatus status = ParkingStatus.Active)
    {
        var admin = new AdministrationService(new InMemoryAdministrationRepository(), new DisabledProvisioningWorker());
        var repo = new InMemoryParkingRepository();
        var parkingWithSpace = new ParkingService(repo, admin);
        var space = new ParkingSpace(Guid.NewGuid(), "BER", Mailbox, "Parkplatz 01", ParkingCategory.Standard, false, false, status, "MAILBOX_STATE_VERIFIED", Now, null);
        repo.TryAdd(space);
        var graph = new FakeGraph(); var availability = new FakeAvailability();
        return (new ParkingReservationService(new InMemoryReservationRepository(), graph, availability, parkingWithSpace, options ?? Open(), new FixedClock(Now)), graph, availability, parkingWithSpace, space.Id);
    }

    private static Task<ParkingReservation> Book(ParkingReservationService s, Guid space, Actor? actor = null, int startHours = 2, int hours = 2, string key = "k1", string tz = "W. Europe Standard Time")
    {
        var a = actor ?? User();
        TimeZoneInfo zone; try { zone = BookingTimeZones.Find(tz); } catch (ValidationException) { zone = TimeZoneInfo.Utc; }
        return s.RequestAsync(a, Auth(a), space, TimeZoneInfo.ConvertTime(Now.AddHours(startHours), zone), TimeZoneInfo.ConvertTime(Now.AddHours(startHours + hours), zone), tz, key, default);
    }

    // ---- gates and validation ------------------------------------------------

    [Theory]
    [InlineData(false, true)]
    [InlineData(true, false)]
    [InlineData(false, false)]
    public async Task BookingWritesNeedBothTheSwitchAndTheApprovedDelegatedScope(bool enabled, bool approved)
    {
        var (service, graph, _, _, space) = Setup(new BookingOptions { WritesEnabled = enabled, DelegatedWriteScopeApproved = approved });
        Assert.Equal("BOOKING_WRITES_NOT_ACTIVATED", (await Assert.ThrowsAsync<WorkflowException>(() => Book(service, space))).Code);
        Assert.Equal(0, graph.Calls);
    }

    [Fact]
    public async Task OnlyVerifiedActiveSpacesCanBeBooked()
    {
        var (service, graph, _, _, space) = Setup(status: ParkingStatus.PendingVerification);
        Assert.Equal("PARKING_SPACE_NOT_VERIFIED", (await Assert.ThrowsAsync<WorkflowException>(() => Book(service, space))).Code);
        Assert.Equal(0, graph.Calls);
    }

    [Fact]
    public async Task BookingIsLocationScoped()
    {
        var (service, graph, _, _, space) = Setup();
        await Assert.ThrowsAsync<AuthorizationException>(() => Book(service, space, User("other", "HAM")));
        Assert.Equal(0, graph.Calls);
    }

    [Theory]
    [InlineData(2, 0, "W. Europe Standard Time", "BOOKING_INTERVAL_INVALID")]
    [InlineData(2, 30, "W. Europe Standard Time", "BOOKING_INTERVAL_INVALID")]
    [InlineData(-3, 1, "W. Europe Standard Time", "BOOKING_START_OUT_OF_WINDOW")]
    [InlineData(24 * 30, 1, "W. Europe Standard Time", "BOOKING_START_OUT_OF_WINDOW")]
    [InlineData(2, 2, "Mars Standard Time", "TIME_ZONE_NOT_ALLOWED")]
    public async Task InvalidIntervalsWindowsAndTimeZonesAreRejectedBeforeAnyCall(int startHours, int hours, string tz, string code)
    {
        var (service, graph, availability, _, space) = Setup();
        Assert.Equal(code, (await Assert.ThrowsAsync<ValidationException>(() => Book(service, space, startHours: startHours, hours: hours, tz: tz))).Code);
        Assert.Equal(0, graph.Calls); Assert.Equal(0, availability.Calls);
    }

    [Fact]
    public async Task AWallClockOffsetThatDoesNotMatchTheZoneIsRejectedBecauseGraphWouldReceiveTheWrongHour()
    {
        var (service, graph, _, _, space) = Setup();
        var wrong = Now.AddHours(2).ToOffset(TimeSpan.FromHours(5));
        var ex = await Assert.ThrowsAsync<ValidationException>(() => service.RequestAsync(User(), Auth(User()), space, wrong, wrong.AddHours(2), "W. Europe Standard Time", "k-off", default));
        Assert.Equal("TIME_ZONE_OFFSET_MISMATCH", ex.Code); Assert.Equal(0, graph.Calls);
    }

    [Fact]
    public async Task MissingIdentityAndIdempotencyKeyAreRejected()
    {
        var (service, _, _, _, space) = Setup();
        await Assert.ThrowsAsync<AuthorizationException>(() => Book(service, space, User("")));
        await Assert.ThrowsAsync<ValidationException>(() => Book(service, space, key: ""));
    }

    // ---- availability is advisory, Exchange decides -----------------------------

    [Theory]
    [InlineData(AvailabilityState.Busy, "BOOKING_CONFLICT")]
    [InlineData(AvailabilityState.OutOfOffice, "BOOKING_CONFLICT")]
    [InlineData(AvailabilityState.Unknown, "AVAILABILITY_UNKNOWN")]
    public async Task BusyOrUnknownAvailabilityBlocksWithoutCreatingAnEvent(AvailabilityState state, string code)
    {
        var (service, graph, availability, _, space) = Setup(); availability.State = state;
        Assert.Equal(code, (await Assert.ThrowsAsync<WorkflowException>(() => Book(service, space))).Code);
        Assert.Equal(0, graph.Creates);
    }

    [Fact]
    public async Task AFreeSlotCreatesAPendingReservationNeverAConfirmedOne()
    {
        var (service, graph, _, _, space) = Setup();
        var reservation = await Book(service, space);
        Assert.Equal(ReservationState.Pending, reservation.State); Assert.Null(reservation.ConfirmedAt);
        Assert.Equal("AWAITING_EXCHANGE_RESPONSE", reservation.OutcomeCode); Assert.NotNull(reservation.GraphEventId);
        Assert.Equal(1, graph.Creates); Assert.Equal(reservation.Id.ToString("N"), graph.LastSpec!.TransactionId); Assert.Equal(Mailbox, graph.LastSpec.MailboxAddress);
    }

    [Fact]
    public async Task AnIdempotentRepeatReturnsTheSameReservationAndCreatesNoSecondEvent()
    {
        var (service, graph, _, _, space) = Setup();
        var first = await Book(service, space); var second = await Book(service, space);
        Assert.Equal(first.Id, second.Id); Assert.Equal(1, graph.Creates);
        await Assert.ThrowsAsync<AuthorizationException>(() => Book(service, space, User("someone-else")));
    }

    [Fact]
    public async Task CompetingOverlappingReservationsAreBlockedLocallyAndAdjacentOnesAreAllowed()
    {
        var (service, graph, _, _, space) = Setup();
        await Book(service, space, startHours: 2, hours: 2, key: "a");
        Assert.Equal("BOOKING_CONFLICT", (await Assert.ThrowsAsync<WorkflowException>(() => Book(service, space, User("u2"), startHours: 3, hours: 2, key: "b"))).Code);
        await Book(service, space, User("u2"), startHours: 4, hours: 1, key: "c");
        Assert.Equal(2, graph.Creates);
    }

    [Fact]
    public async Task AnAmbiguousCreateRequiresReconciliationAndIsNotRetried()
    {
        var (service, graph, _, _, space) = Setup(); graph.CreateThrows = new AmbiguousOutcomeException("WRITE_OUTCOME_UNKNOWN");
        var reservation = await Book(service, space);
        Assert.Equal((ReservationState.RequiresReconciliation, "WRITE_OUTCOME_UNKNOWN"), (reservation.State, reservation.OutcomeCode)); Assert.Equal(1, graph.Creates);
        graph.CreateThrows = null;
        Assert.Equal(reservation.Id, (await Book(service, space)).Id); Assert.Equal(1, graph.Creates);
        Assert.Equal("BOOKING_CONFLICT", (await Assert.ThrowsAsync<WorkflowException>(() => Book(service, space, User("u2"), key: "other"))).Code);
    }

    [Fact]
    public async Task APermissionFailureIsAnUnknownStateNotASuccess()
    {
        var (s2, graph2, _, _, space2) = Setup(); graph2.CreateThrows = new IntegrationException("BOOKING_PERMISSION_DENIED");
        var reservation = await Book(s2, space2);
        Assert.Equal((ReservationState.Unknown, "BOOKING_PERMISSION_DENIED"), (reservation.State, reservation.OutcomeCode));
    }

    // ---- Exchange response tracking ---------------------------------------------

    [Theory]
    [InlineData("accepted", ReservationState.Accepted, "EXCHANGE_ACCEPTED")]
    [InlineData("declined", ReservationState.Declined, "EXCHANGE_DECLINED")]
    [InlineData("none", ReservationState.Pending, "AWAITING_EXCHANGE_RESPONSE")]
    [InlineData("notResponded", ReservationState.Pending, "AWAITING_EXCHANGE_RESPONSE")]
    [InlineData("tentativelyAccepted", ReservationState.Pending, "AWAITING_EXCHANGE_RESPONSE")]
    [InlineData("somethingNew", ReservationState.Unknown, "RESPONSE_UNRECOGNIZED")]
    [InlineData(null, ReservationState.Unknown, "RESOURCE_ATTENDEE_NOT_FOUND")]
    public async Task OnlyTheReadBackResourceResponseDecidesTheState(string? response, ReservationState state, string code)
    {
        var (service, graph, _, _, space) = Setup(); var reservation = await Book(service, space);
        graph.Status = new BookingEventStatus(reservation.GraphEventId!, false, response);
        var refreshed = await service.RefreshAsync(reservation.Id, User(), default);
        Assert.Equal((state, code), (refreshed.State, refreshed.OutcomeCode));
        Assert.Equal(state == ReservationState.Accepted, refreshed.ConfirmedAt is not null);
    }

    [Fact]
    public async Task ExternalCancellationAndRemovalInOutlookAreReconciled()
    {
        var (service, graph, _, _, space) = Setup(); var reservation = await Book(service, space);
        graph.Status = new BookingEventStatus(reservation.GraphEventId!, true, "accepted");
        Assert.Equal("EVENT_CANCELLED", (await service.RefreshAsync(reservation.Id, User(), default)).OutcomeCode);
        var (s2, g2, _, _, sp2) = Setup(); var r2 = await Book(s2, sp2); g2.Status = null;
        var gone = await s2.RefreshAsync(r2.Id, User(), default);
        Assert.Equal((ReservationState.Cancelled, "EVENT_REMOVED_EXTERNALLY"), (gone.State, gone.OutcomeCode));
    }

    [Fact]
    public async Task AReadFailureNeverDowngradesAnAcceptedReservationAndMarksOthersUnknown()
    {
        var (service, graph, _, _, space) = Setup(); var reservation = await Book(service, space);
        graph.Status = new BookingEventStatus(reservation.GraphEventId!, false, "accepted"); await service.RefreshAsync(reservation.Id, User(), default);
        graph.GetThrows = new IntegrationException("GRAPH_UNAVAILABLE");
        Assert.Equal(ReservationState.Accepted, (await service.RefreshAsync(reservation.Id, User(), default)).State);
        var (s2, g2, _, _, sp2) = Setup(); var r2 = await Book(s2, sp2); g2.GetThrows = new IntegrationException("GRAPH_UNAVAILABLE");
        Assert.Equal(ReservationState.Unknown, (await s2.RefreshAsync(r2.Id, User(), default)).State);
    }

    [Fact]
    public async Task ADeclinedReservationFreesTheSlotForAnotherBooking()
    {
        var (service, graph, _, _, space) = Setup(); var first = await Book(service, space, key: "a");
        graph.Status = new BookingEventStatus(first.GraphEventId!, false, "declined"); await service.RefreshAsync(first.Id, User(), default);
        var second = await Book(service, space, User("u2"), key: "b");
        Assert.Equal(ReservationState.Pending, second.State);
    }

    // ---- cancellation -----------------------------------------------------------

    [Fact]
    public async Task OnlyTheOrganizerMayCancelAndTheCancellationIsRecorded()
    {
        var (service, graph, _, _, space) = Setup(); var reservation = await Book(service, space);
        Assert.Equal("ONLY_THE_ORGANIZER_MAY_CANCEL", (await Assert.ThrowsAsync<AuthorizationException>(() => service.CancelAsync(reservation.Id, User("intruder"), default))).Code);
        Assert.Equal(0, graph.Cancels);
        var cancelled = await service.CancelAsync(reservation.Id, User(), default);
        Assert.Equal((ReservationState.Cancelled, "CANCELLED"), (cancelled.State, cancelled.OutcomeCode)); Assert.Equal(1, graph.Cancels);
        await service.CancelAsync(reservation.Id, User(), default); Assert.Equal(1, graph.Cancels);
    }

    [Fact]
    public async Task AnAmbiguousCancellationRequiresReconciliation()
    {
        var (service, graph, _, _, space) = Setup(); var reservation = await Book(service, space); graph.CancelThrows = new AmbiguousOutcomeException("WRITE_OUTCOME_UNKNOWN");
        Assert.Equal(ReservationState.RequiresReconciliation, (await service.CancelAsync(reservation.Id, User(), default)).State);
    }

    [Fact]
    public async Task CancellationFromAnotherLocationIsDenied()
    {
        var (service, _, _, _, space) = Setup(); var reservation = await Book(service, space);
        await Assert.ThrowsAsync<AuthorizationException>(() => service.CancelAsync(reservation.Id, User("user-1", "HAM"), default));
    }

    // ---- Graph client contract --------------------------------------------------

    private static GraphBookingClient Client(Func<HttpRequestMessage, HttpResponseMessage> handler, FakeTokens? tokens = null) =>
        new(new HttpClient(new Handler(handler)) { BaseAddress = new("https://graph.microsoft.com/v1.0/") }, tokens ?? new FakeTokens(), (_, _) => Task.CompletedTask);
    private static HttpResponseMessage Json(HttpStatusCode code, string json) => new(code) { Content = new StringContent(json, Encoding.UTF8, "application/json") };
    private static BookingEventSpec Spec() => new(Mailbox, "Parkplatz 01", Now.AddHours(2), Now.AddHours(4), "W. Europe Standard Time", "abc123");

    [Fact]
    public async Task TheCreateRequestIsAFixedTypedEventForTheResourceWithADelegatedWriteScope()
    {
        string? body = null; HttpRequestMessage? seen = null; var tokens = new FakeTokens();
        var client = Client(r => { seen = r; body = r.Content!.ReadAsStringAsync().Result; return Json(HttpStatusCode.Created, "{\"id\":\"AAMkADEx_abc=\"}"); }, tokens);
        Assert.Equal("AAMkADEx_abc=", await client.CreateEventAsync(Spec(), default));
        Assert.Equal(HttpMethod.Post, seen!.Method); Assert.Equal("/v1.0/me/events", seen.RequestUri!.AbsolutePath);
        Assert.Equal(["Calendars.ReadWrite"], tokens.LastScopes!.ToArray());
        using var doc = System.Text.Json.JsonDocument.Parse(body!);
        Assert.Equal(["subject", "start", "end", "attendees", "locations", "isReminderOn", "transactionId"], doc.RootElement.EnumerateObject().Select(p => p.Name).ToArray());
        Assert.Equal("resource", doc.RootElement.GetProperty("attendees")[0].GetProperty("type").GetString());
        Assert.Equal("abc123", doc.RootElement.GetProperty("transactionId").GetString());
        Assert.Equal("Parkplatz-Reservierung", doc.RootElement.GetProperty("subject").GetString());
    }

    [Fact]
    public async Task ThrottledCreateIsRetriedBoundedAndServerErrorsAreAmbiguous()
    {
        var calls = 0;
        var throttled = Client(_ => ++calls == 1 ? new(HttpStatusCode.TooManyRequests) : Json(HttpStatusCode.Created, "{\"id\":\"AAMkADEx_abc=\"}"));
        await throttled.CreateEventAsync(Spec(), default); Assert.Equal(2, calls);
        var errors = 0;
        await Assert.ThrowsAsync<AmbiguousOutcomeException>(() => Client(_ => { errors++; return new(HttpStatusCode.BadGateway); }).CreateEventAsync(Spec(), default)); Assert.Equal(1, errors);
        await Assert.ThrowsAsync<AmbiguousOutcomeException>(() => Client(_ => throw new TaskCanceledException()).CreateEventAsync(Spec(), default));
    }

    [Theory]
    [InlineData(HttpStatusCode.Forbidden, "BOOKING_PERMISSION_DENIED")]
    [InlineData(HttpStatusCode.Unauthorized, "BOOKING_PERMISSION_DENIED")]
    [InlineData(HttpStatusCode.Conflict, "BOOKING_CONFLICT")]
    [InlineData(HttpStatusCode.BadRequest, "GRAPH_REQUEST_REJECTED")]
    public async Task GraphErrorsMapToSafeCodes(HttpStatusCode status, string code) =>
        Assert.Equal(code, (await Assert.ThrowsAsync<IntegrationException>(() => Client(_ => new(status)).CreateEventAsync(Spec(), default))).Code);

    [Fact]
    public async Task ReadBackUsesOnlyTheResourceAttendeesResponse()
    {
        const string json = "{\"id\":\"AAMkADEx_abc=\",\"isCancelled\":false,\"attendees\":[{\"emailAddress\":{\"address\":\"someone@contoso.example\"},\"status\":{\"response\":\"accepted\"}},{\"emailAddress\":{\"address\":\"ph-park-01@contoso.example\"},\"status\":{\"response\":\"declined\"}}]}";
        var status = await Client(_ => Json(HttpStatusCode.OK, json)).GetEventAsync("AAMkADEx_abc=", Mailbox, default);
        Assert.Equal("declined", status!.ResourceResponse); Assert.False(status.IsCancelled);
        Assert.Null(await Client(_ => new(HttpStatusCode.NotFound)).GetEventAsync("AAMkADEx_abc=", Mailbox, default));
    }

    [Fact]
    public async Task CancelPostsToTheCancelActionAndEventIdsAreValidated()
    {
        HttpRequestMessage? seen = null;
        await Client(r => { seen = r; return new(HttpStatusCode.Accepted); }).CancelEventAsync("AAMkADEx_abc=", default);
        Assert.Equal(HttpMethod.Post, seen!.Method); Assert.EndsWith("/cancel", seen.RequestUri!.AbsolutePath);
        var calls = 0; var client = Client(_ => { calls++; return new(HttpStatusCode.OK); });
        foreach (var bad in new[] { "../users", "a/b", "x y", "short", "a?b=c" }) { await Assert.ThrowsAsync<ValidationException>(() => client.CancelEventAsync(bad, default)); await Assert.ThrowsAsync<ValidationException>(() => client.GetEventAsync(bad, Mailbox, default)); }
        Assert.Equal(0, calls);
    }

    [Fact]
    public async Task ADeniedDelegatedScopeStopsBeforeAnyHttpCall()
    {
        var calls = 0;
        var client = Client(_ => { calls++; return new(HttpStatusCode.OK); }, new FakeTokens { Throw = new IntegrationAuthorizationException("DELEGATED_SCOPE_NOT_ALLOWED") });
        Assert.Equal("DELEGATED_SCOPE_NOT_ALLOWED", (await Assert.ThrowsAsync<IntegrationAuthorizationException>(() => client.CreateEventAsync(Spec(), default))).Code);
        Assert.Equal(0, calls);
    }

    [Fact]
    public void TheWebApplicationsTokenProviderStillRefusesTheBookingWriteScope()
    {
        var root = AppContext.BaseDirectory; while (root is not null && !File.Exists(Path.Combine(root, "PlaceHub.slnx"))) root = Path.GetDirectoryName(root);
        var source = File.ReadAllText(Path.Combine(root!, "src", "PlaceHub.Web", "Microsoft365Authentication.cs"));
        Assert.DoesNotContain("Calendars.ReadWrite", source);
        var program = File.ReadAllText(Path.Combine(root!, "src", "PlaceHub.Web", "Program.cs"));
        Assert.DoesNotContain("Calendars.ReadWrite", program);
    }

    // ---- helpers ----------------------------------------------------------------

    private sealed class FixedClock(DateTimeOffset now) : TimeProvider { public override DateTimeOffset GetUtcNow() => now; }
    private sealed class FakeTokens : IDelegatedTokenProvider
    {
        public IReadOnlySet<string>? LastScopes; public Exception? Throw;
        public Task<string> GetTokenAsync(IReadOnlySet<string> scopes, CancellationToken cancellationToken) { LastScopes = scopes; return Throw is null ? Task.FromResult("synthetic-token") : throw Throw; }
    }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> handler) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => Task.FromResult(handler(request));
    }
    private sealed class FakeAvailability : IAvailabilityReader
    {
        public int Calls; public AvailabilityState State = AvailabilityState.Free;
        public Task<IReadOnlyList<ResourceAvailability>> ReadAsync(AvailabilityRequest request, ReadAuthorizationContext authorization, CancellationToken cancellationToken)
        { Calls++; return Task.FromResult<IReadOnlyList<ResourceAvailability>>([new(request.ResourceMailboxes[0], State, request.Start, request.End, "test")]); }
    }
    private sealed class FakeGraph : IBookingGraphClient
    {
        public int Calls, Creates, Cancels; public BookingEventSpec? LastSpec; public Exception? CreateThrows, CancelThrows, GetThrows; public BookingEventStatus? Status;
        public Task<string> CreateEventAsync(BookingEventSpec spec, CancellationToken cancellationToken)
        { Calls++; Creates++; LastSpec = spec; if (CreateThrows is not null) throw CreateThrows; return Task.FromResult("AAMkAD-" + Creates + "_evt="); }
        public Task<BookingEventStatus?> GetEventAsync(string eventId, string resourceMailbox, CancellationToken cancellationToken)
        { Calls++; if (GetThrows is not null) throw GetThrows; return Task.FromResult(Status); }
        public Task CancelEventAsync(string eventId, CancellationToken cancellationToken)
        { Calls++; Cancels++; if (CancelThrows is not null) throw CancelThrows; return Task.CompletedTask; }
    }
}
