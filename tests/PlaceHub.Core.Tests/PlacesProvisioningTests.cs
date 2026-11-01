using System.Net;
using System.Text;
using PlaceHub.Core;
using Xunit;

namespace PlaceHub.Core.Tests;

public sealed class PlacesProvisioningTests
{
    private const string Scope = "BER";
    private static Actor Office() => new("office", PlaceHubRole.OfficeManager, new HashSet<string> { Scope, "BOOTSTRAP-DEV" });
    private static Actor Admin() => new("admin", PlaceHubRole.SystemAdministrator, new HashSet<string> { Scope, "BOOTSTRAP-DEV" });

    private static AdministrationRequest Approved(PlacesWriteSpec spec, OperationKind op = OperationKind.Create, string scope = Scope)
    {
        var request = new AdministrationRequest(ResourceSpecification.ForPlaces(op, scope, spec), Office(), Guid.NewGuid().ToString("N"), "cor");
        request.Submit(Office(), request.Version); request.Approve(Admin(), request.Version);
        return request;
    }

    private static BootstrapManifest Manifest(string status = BootstrapManifest.ApprovedStatus, string env = "development") =>
        new(env, status, [new("first-building", "Synthetic Test Building")]);

    private static PlacesWriteOptions Options(bool enabled = true, bool mailbox = false, string env = "development", int attempts = 3) =>
        new() { Enabled = enabled, Environment = env, MailboxCreationApproved = mailbox, ReadBackAttempts = attempts, ReadBackDelay = TimeSpan.Zero };

    private static PlacesProvisioningWorker Worker(FakePlaces fake, PlacesWriteOptions? options = null, BootstrapManifest? manifest = null, IBootstrapGuard? guard = null, PlacesInventory? inventory = null) =>
        new(fake, new FakeInventory(inventory ?? new(0, 0, 0, 0, 0, 0, 0, 0, true, DateTimeOffset.UtcNow)), guard ?? new InMemoryBootstrapGuard(), manifest ?? Manifest(), options ?? Options(), (_, _) => Task.CompletedTask);

    // ---- typed validation -------------------------------------------------

    [Theory]
    [InlineData(PlaceType.Building, "B1", "parent", OperationKind.Create, "PLACE_PARENT_NOT_ALLOWED")]
    [InlineData(PlaceType.Floor, "F1", null, OperationKind.Create, "PLACE_PARENT_REQUIRED")]
    [InlineData(PlaceType.Desk, "D1", "bad id", OperationKind.Create, "PLACE_PARENT_REQUIRED")]
    [InlineData(PlaceType.Floor, "F1\"; drop", "p", OperationKind.Create, "PLACE_DISPLAY_NAME_INVALID")]
    [InlineData(PlaceType.Floor, "", "p", OperationKind.Create, "PLACE_DISPLAY_NAME_INVALID")]
    [InlineData(PlaceType.Floor, "F1", "p", OperationKind.Disable, "PLACES_OPERATION_NOT_ALLOWED")]
    [InlineData(PlaceType.Floor, "F1", "p", OperationKind.Reconcile, "PLACES_OPERATION_NOT_ALLOWED")]
    [InlineData(PlaceType.Floor, "F1", "p", OperationKind.Update, "PLACE_TARGET_REQUIRED")]
    public void InvalidPlacesPayloadsAreRejected(PlaceType kind, string name, string? parent, OperationKind op, string code)
    {
        var ex = Assert.Throws<ValidationException>(() => new PlacesWriteSpec(kind, name, parent).Validate(op));
        Assert.Equal(code, ex.Code);
    }

    [Fact]
    public void UpdateCannotReparentAndCreateCannotCarryATarget()
    {
        Assert.Equal("PLACE_REPARENT_NOT_SUPPORTED", Assert.Throws<ValidationException>(() => new PlacesWriteSpec(PlaceType.Floor, "F", "p", TargetPlaceId: "t").Validate(OperationKind.Update)).Code);
        Assert.Equal("PLACE_TARGET_NOT_ALLOWED_ON_CREATE", Assert.Throws<ValidationException>(() => new PlacesWriteSpec(PlaceType.Floor, "F", "p", TargetPlaceId: "t").Validate(OperationKind.Create)).Code);
    }

    [Fact]
    public void BootstrapEntryIsOnlyValidForBuildingCreate()
    {
        Assert.Equal("BOOTSTRAP_SPEC_INVALID", Assert.Throws<ValidationException>(() => new PlacesWriteSpec(PlaceType.Floor, "F", "p", BootstrapEntryId: "first-building").Validate(OperationKind.Create)).Code);
        new PlacesWriteSpec(PlaceType.Building, "B", null, BootstrapEntryId: "first-building").Validate(OperationKind.Create);
    }

    [Fact]
    public void RequestRejectsMismatchedPlacesPayload()
    {
        var spec = new ResourceSpecification(ResourceKind.DeskPool, OperationKind.Create, Scope, "B", "1", "N", "Name", 5, null, Places: new PlacesWriteSpec(PlaceType.Building, "B", null));
        Assert.Equal("PLACES_PAYLOAD_MISMATCH", Assert.Throws<ValidationException>(() => new AdministrationRequest(spec, Office(), "k", "c")).Code);
    }

    // ---- worker gates -----------------------------------------------------

    [Fact]
    public async Task WorkerRefusesWhileDisabledAndCallsNothing()
    {
        var fake = new FakePlaces();
        var ex = await Assert.ThrowsAsync<WorkflowException>(() => Worker(fake, Options(enabled: false)).ExecuteAsync(Approved(new(PlaceType.Building, "B", null)), default));
        Assert.Equal("PLACES_WRITE_NOT_ACTIVATED", ex.Code); Assert.Equal(0, fake.Calls);
    }

    [Fact]
    public async Task WorkerRejectsUnapprovedRequest()
    {
        var request = new AdministrationRequest(ResourceSpecification.ForPlaces(OperationKind.Create, Scope, new(PlaceType.Building, "B", null)), Office(), "k", "c");
        var fake = new FakePlaces();
        Assert.Equal("APPROVAL_INTEGRITY_FAILED", (await Assert.ThrowsAsync<WorkflowException>(() => Worker(fake).ExecuteAsync(request, default))).Code);
        Assert.Equal(0, fake.Calls);
    }

    [Fact]
    public async Task WorkspaceAndDeskCreationNeedSeparateMailboxApproval()
    {
        var fake = new FakePlaces(); fake.Add(PlaceType.Section, "s1", null, "S");
        foreach (var kind in new[] { PlaceType.Workspace, PlaceType.Desk })
        {
            var result = await Worker(fake).ExecuteAsync(Approved(new(kind, "W", "s1")), default);
            Assert.Equal((RequestState.Failed, "MAILBOX_CREATE_NOT_APPROVED"), (result.State, result.OutcomeCode));
        }
        Assert.Equal(0, fake.Creates);
        var approved = await Worker(fake, Options(mailbox: true)).ExecuteAsync(Approved(new(PlaceType.Desk, "D1", "s1")), default);
        Assert.Equal(RequestState.Succeeded, approved.State);
    }

    // ---- create / verify --------------------------------------------------

    [Fact]
    public async Task CreateFloorUnderBuildingIsVerifiedByReadBack()
    {
        var fake = new FakePlaces(); fake.Add(PlaceType.Building, "b-id", "b-stable", "Synthetic Test Building");
        var result = await Worker(fake).ExecuteAsync(Approved(new(PlaceType.Floor, "F1", "b-stable")), default);
        Assert.Equal((RequestState.Succeeded, "PLACE_CREATED_VERIFIED"), (result.State, result.OutcomeCode));
        Assert.NotNull(result.PlaceId); Assert.Equal(1, fake.Creates);
        Assert.Equal("b-id", fake.LastParentGraphId);
    }

    [Fact]
    public async Task WrongParentTypeOrMissingParentCreatesNothing()
    {
        var fake = new FakePlaces(); fake.Add(PlaceType.Floor, "f1", null, "F");
        var result = await Worker(fake).ExecuteAsync(Approved(new(PlaceType.Section, "S", "does-not-exist")), default);
        Assert.Equal("PARENT_NOT_FOUND_OR_WRONG_TYPE", result.OutcomeCode);
        // a desk may not hang under a floor
        var desk = await Worker(fake, Options(mailbox: true)).ExecuteAsync(Approved(new(PlaceType.Desk, "D", "f1")), default);
        Assert.Equal("PARENT_NOT_FOUND_OR_WRONG_TYPE", desk.OutcomeCode); Assert.Equal(0, fake.Creates);
    }

    [Fact]
    public async Task ExistingDuplicateIsNeverCreatedAgain()
    {
        var fake = new FakePlaces(); fake.Add(PlaceType.Building, "b", "bs", "B"); fake.Add(PlaceType.Floor, "f", "fs", "F1", "b");
        var result = await Worker(fake).ExecuteAsync(Approved(new(PlaceType.Floor, "f1", "bs")), default);
        Assert.Equal((RequestState.RequiresReconciliation, "DUPLICATE_EXISTS"), (result.State, result.OutcomeCode));
        Assert.Equal(0, fake.Creates);
    }

    [Fact]
    public async Task AmbiguousCreateOutcomeRequiresReconciliationAndIsNotRetried()
    {
        var fake = new FakePlaces { CreateThrows = new AmbiguousOutcomeException("WRITE_OUTCOME_UNKNOWN") };
        var result = await Worker(fake).ExecuteAsync(Approved(new(PlaceType.Building, "B", null)), default);
        Assert.Equal((RequestState.RequiresReconciliation, "WRITE_OUTCOME_UNKNOWN"), (result.State, result.OutcomeCode));
        Assert.Equal(1, fake.Creates);
    }

    [Fact]
    public async Task PropagationDelayIsRetriedBoundedThenReportedPending()
    {
        var delayed = new FakePlaces { HideReadsFor = 2 };
        Assert.Equal(RequestState.Succeeded, (await Worker(delayed).ExecuteAsync(Approved(new(PlaceType.Building, "B", null)), default)).State);
        var never = new FakePlaces { HideReadsFor = int.MaxValue };
        var result = await Worker(never).ExecuteAsync(Approved(new(PlaceType.Building, "B2", null)), default);
        Assert.Equal((RequestState.PendingPropagation, "PLACE_PENDING_PROPAGATION"), (result.State, result.OutcomeCode));
        Assert.Equal(1, never.Creates);
    }

    [Fact]
    public async Task ReadAfterWriteMismatchRequiresReconciliation()
    {
        var fake = new FakePlaces { ReadBackName = "Different" };
        var result = await Worker(fake).ExecuteAsync(Approved(new(PlaceType.Building, "B", null)), default);
        Assert.Equal((RequestState.RequiresReconciliation, "READ_AFTER_WRITE_MISMATCH"), (result.State, result.OutcomeCode));
    }

    [Fact]
    public async Task PermissionFailureIsReportedWithoutRetry()
    {
        var fake = new FakePlaces { CreateThrows = new IntegrationException("GRAPH_WRITE_PERMISSION_DENIED") };
        var result = await Worker(fake).ExecuteAsync(Approved(new(PlaceType.Building, "B", null)), default);
        Assert.Equal((RequestState.Failed, "GRAPH_WRITE_PERMISSION_DENIED"), (result.State, result.OutcomeCode)); Assert.Equal(1, fake.Creates);
    }

    [Fact]
    public async Task UpdateVerifiesTypeAndReadsBack()
    {
        var fake = new FakePlaces(); fake.Add(PlaceType.Floor, "f1", "fs", "Old");
        var spec = new PlacesWriteSpec(PlaceType.Floor, "New", null, TargetPlaceId: "f1");
        var result = await Worker(fake).ExecuteAsync(Approved(spec, OperationKind.Update), default);
        Assert.Equal((RequestState.Succeeded, "PLACE_UPDATED_VERIFIED"), (result.State, result.OutcomeCode));
        var wrongType = await Worker(fake).ExecuteAsync(Approved(spec with { Kind = PlaceType.Building }, OperationKind.Update), default);
        Assert.Equal("PLACE_TYPE_MISMATCH", wrongType.OutcomeCode);
    }

    // ---- bootstrap --------------------------------------------------------

    private static PlacesWriteSpec Bootstrap(string name = "Synthetic Test Building") => new(PlaceType.Building, name, null, BootstrapEntryId: "first-building");

    [Fact]
    public async Task BootstrapSucceedsOnceWhenEverythingIsSatisfied()
    {
        var fake = new FakePlaces(); var guard = new InMemoryBootstrapGuard();
        var first = await Worker(fake, guard: guard).ExecuteAsync(Approved(Bootstrap(), scope: "BOOTSTRAP-DEV"), default);
        Assert.Equal(RequestState.Succeeded, first.State);
        var second = await Worker(new FakePlaces(), guard: guard).ExecuteAsync(Approved(Bootstrap(), scope: "BOOTSTRAP-DEV"), default);
        Assert.Equal("BOOTSTRAP_ALREADY_USED_OR_RUNNING", second.OutcomeCode);
    }

    [Theory]
    [InlineData("prod", "development", "APPROVED_BY_PROJECT_OWNER", "BOOTSTRAP_DEVELOPMENT_ONLY")]
    [InlineData("development", "prod", "APPROVED_BY_PROJECT_OWNER", "BOOTSTRAP_DEVELOPMENT_ONLY")]
    [InlineData("development", "development", "PENDING_OWNER_DEFINITION", "BOOTSTRAP_MANIFEST_NOT_APPROVED")]
    public async Task BootstrapIsDevelopmentOnlyAndNeedsAnApprovedManifest(string optionEnv, string manifestEnv, string status, string code)
    {
        var fake = new FakePlaces();
        var result = await Worker(fake, Options(env: optionEnv), Manifest(status, manifestEnv)).ExecuteAsync(Approved(Bootstrap(), scope: "BOOTSTRAP-DEV"), default);
        Assert.Equal(code, result.OutcomeCode); Assert.Equal(0, fake.Creates);
    }

    [Fact]
    public async Task BootstrapRejectsArbitraryNamesAndUnknownEntries()
    {
        var fake = new FakePlaces();
        Assert.Equal("BOOTSTRAP_NAME_NOT_IN_MANIFEST", (await Worker(fake).ExecuteAsync(Approved(Bootstrap("Made Up HQ"), scope: "BOOTSTRAP-DEV"), default)).OutcomeCode);
        var unknown = new PlacesWriteSpec(PlaceType.Building, "Synthetic Test Building", null, BootstrapEntryId: "other");
        Assert.Equal("BOOTSTRAP_ENTRY_UNKNOWN", (await Worker(fake).ExecuteAsync(Approved(unknown, scope: "BOOTSTRAP-DEV"), default)).OutcomeCode);
        Assert.Equal(0, fake.Creates);
    }

    [Fact]
    public async Task BootstrapRequiresVerifiedEmptyBuildingInventory()
    {
        var fake = new FakePlaces();
        var existing = new PlacesInventory(1, 0, 0, 0, 0, 0, 0, 0, true, DateTimeOffset.UtcNow);
        Assert.Equal("BOOTSTRAP_BUILDINGS_EXIST", (await Worker(fake, inventory: existing).ExecuteAsync(Approved(Bootstrap(), scope: "BOOTSTRAP-DEV"), default)).OutcomeCode);
        var incomplete = new PlacesInventory(0, 0, 0, 0, 0, 0, 0, 0, false, DateTimeOffset.UtcNow);
        Assert.Equal("BOOTSTRAP_INVENTORY_INCOMPLETE", (await Worker(fake, inventory: incomplete).ExecuteAsync(Approved(Bootstrap(), scope: "BOOTSTRAP-DEV"), default)).OutcomeCode);
        Assert.Equal(0, fake.Creates);
    }

    [Fact]
    public async Task ConcurrentBootstrapRequestsCreateExactlyOneBuilding()
    {
        var fake = new FakePlaces(); var guard = new InMemoryBootstrapGuard();
        var requests = Enumerable.Range(0, 8).Select(_ => Approved(Bootstrap(), scope: "BOOTSTRAP-DEV")).ToArray();
        var results = await Task.WhenAll(requests.Select(r => Task.Run(() => Worker(fake, guard: guard).ExecuteAsync(r, default))));
        Assert.Equal(1, results.Count(r => r.State == RequestState.Succeeded));
        Assert.Equal(1, fake.Creates);
    }

    [Fact]
    public async Task AmbiguousBootstrapKeepsTheGuardClaimed()
    {
        var guard = new InMemoryBootstrapGuard();
        var first = await Worker(new FakePlaces { CreateThrows = new AmbiguousOutcomeException("WRITE_OUTCOME_UNKNOWN") }, guard: guard).ExecuteAsync(Approved(Bootstrap(), scope: "BOOTSTRAP-DEV"), default);
        Assert.Equal(RequestState.RequiresReconciliation, first.State);
        var retry = await Worker(new FakePlaces(), guard: guard).ExecuteAsync(Approved(Bootstrap(), scope: "BOOTSTRAP-DEV"), default);
        Assert.Equal("BOOTSTRAP_ALREADY_USED_OR_RUNNING", retry.OutcomeCode);
    }

    [Fact]
    public void BootstrapRequesterCannotApproveOwnRequest()
    {
        var admin = Admin();
        var request = new AdministrationRequest(ResourceSpecification.ForPlaces(OperationKind.Create, "BOOTSTRAP-DEV", Bootstrap()), admin, "k", "c");
        request.Submit(admin, request.Version);
        Assert.Equal("SELF_APPROVAL_DENIED", Assert.Throws<AuthorizationException>(() => request.Approve(admin, request.Version)).Code);
    }

    [Fact]
    public void BootstrapNeedsTheOwnerControlledScopeAndNoTenantWideAccess()
    {
        var withoutScope = new Actor("a", PlaceHubRole.OfficeManager, new HashSet<string> { Scope });
        Assert.Equal("LOCATION_OUT_OF_SCOPE", Assert.Throws<AuthorizationException>(() => new AdministrationRequest(ResourceSpecification.ForPlaces(OperationKind.Create, "BOOTSTRAP-DEV", Bootstrap()), withoutScope, "k", "c")).Code);
    }

    [Fact]
    public void ManifestFileFormatLoadsAndIsNotApprovedByDefault()
    {
        var manifest = BootstrapManifest.Load("{\"environment\":\"development\",\"status\":\"PENDING_OWNER_DEFINITION\",\"entries\":[]}");
        Assert.Equal("BOOTSTRAP_MANIFEST_NOT_APPROVED", Assert.Throws<ValidationException>(() => manifest.Resolve("x", "y")).Code);
    }

    // ---- Graph HTTP adapter -----------------------------------------------

    [Fact]
    public async Task GraphCreateSendsOnlyTheTypedBodyWithBearerToken()
    {
        string? body = null; HttpRequestMessage? seen = null;
        var client = Graph(r => { seen = r; body = r.Content!.ReadAsStringAsync().Result; return Json(HttpStatusCode.Created, "{\"@odata.type\":\"#microsoft.graph.floor\",\"id\":\"i1\",\"placeId\":\"p1\",\"parentId\":\"b1\",\"displayName\":\"F1\"}"); });
        var created = await client.CreateAsync(new(PlaceType.Floor, "F1", "ignored", ["t1"]), "b1", default);
        Assert.Equal(HttpMethod.Post, seen!.Method); Assert.Equal("/v1.0/places", seen.RequestUri!.AbsolutePath);
        Assert.Equal("Bearer", seen.Headers.Authorization!.Scheme);
        using var doc = System.Text.Json.JsonDocument.Parse(body!);
        Assert.Equal(["@odata.type", "displayName", "parentId", "tags"], doc.RootElement.EnumerateObject().Select(p => p.Name).ToArray());
        Assert.Equal("microsoft.graph.floor", doc.RootElement.GetProperty("@odata.type").GetString());
        Assert.Equal("p1", created.StablePlaceId);
    }

    [Fact]
    public async Task GraphThrottledCreateIsRetriedBecauseTheServerRejectedIt()
    {
        var calls = 0;
        var client = Graph(_ => ++calls == 1 ? new(HttpStatusCode.TooManyRequests) : Json(HttpStatusCode.Created, "{\"@odata.type\":\"#microsoft.graph.building\",\"id\":\"i\",\"displayName\":\"B\"}"));
        await client.CreateAsync(new(PlaceType.Building, "B", null), "", default);
        Assert.Equal(2, calls);
    }

    [Fact]
    public async Task GraphServerErrorOnCreateIsAmbiguousAndNotRetried()
    {
        var calls = 0;
        var client = Graph(_ => { calls++; return new(HttpStatusCode.BadGateway); });
        await Assert.ThrowsAsync<AmbiguousOutcomeException>(() => client.CreateAsync(new(PlaceType.Building, "B", null), "", default));
        Assert.Equal(1, calls);
    }

    [Fact]
    public async Task GraphTimeoutOnCreateIsAmbiguous()
    {
        var client = new GraphPlacesWriteClient(new HttpClient(new StubHandler(_ => throw new TaskCanceledException())) { BaseAddress = new("https://graph.microsoft.com/v1.0/") }, new FixedToken());
        await Assert.ThrowsAsync<AmbiguousOutcomeException>(() => client.CreateAsync(new(PlaceType.Building, "B", null), "", default));
    }

    [Theory]
    [InlineData(HttpStatusCode.Forbidden, "GRAPH_WRITE_PERMISSION_DENIED")]
    [InlineData(HttpStatusCode.Unauthorized, "GRAPH_WRITE_PERMISSION_DENIED")]
    [InlineData(HttpStatusCode.Conflict, "PLACE_CONFLICT")]
    [InlineData(HttpStatusCode.BadRequest, "GRAPH_REQUEST_REJECTED")]
    public async Task GraphErrorsMapToSafeCodes(HttpStatusCode status, string code)
    {
        var client = Graph(_ => new(status));
        Assert.Equal(code, (await Assert.ThrowsAsync<IntegrationException>(() => client.CreateAsync(new(PlaceType.Building, "B", null), "", default))).Code);
    }

    [Fact]
    public async Task GraphGetMapsNotFoundToNullAndRejectsUnsafeIdsBeforeAnyRequest()
    {
        var calls = 0;
        var client = Graph(_ => { calls++; return new(HttpStatusCode.NotFound); });
        Assert.Null(await client.GetAsync("missing", default)); Assert.Equal(1, calls);
        await Assert.ThrowsAsync<ValidationException>(() => client.GetAsync("../users", default));
        await Assert.ThrowsAsync<ValidationException>(() => client.UpdateAsync("a/b", new(PlaceType.Floor, "F", null, TargetPlaceId: "a"), default));
        Assert.Equal(1, calls);
    }

    [Fact]
    public async Task GraphListFollowsOnlyTrustedNextLinks()
    {
        var client = Graph(_ => Json(HttpStatusCode.OK, "{\"value\":[],\"@odata.nextLink\":\"https://evil.example/v1.0/places/x\"}"));
        Assert.Equal("GRAPH_NEXT_LINK_REJECTED", (await Assert.ThrowsAsync<IntegrationException>(() => client.ListAsync(PlaceType.Building, default))).Code);
    }

    [Fact]
    public async Task MissingWorkerCredentialFailsBeforeAnyHttpCall()
    {
        var calls = 0;
        var client = new GraphPlacesWriteClient(new HttpClient(new StubHandler(_ => { calls++; return new(HttpStatusCode.OK); })) { BaseAddress = new("https://graph.microsoft.com/v1.0/") }, new UnavailableWorkerTokenProvider());
        Assert.Equal("WORKER_CREDENTIAL_UNAVAILABLE", (await Assert.ThrowsAsync<IntegrationConfigurationException>(() => client.CreateAsync(new(PlaceType.Building, "B", null), "", default))).Code);
        Assert.Equal(0, calls);
    }

    // ---- helpers ----------------------------------------------------------

    private static GraphPlacesWriteClient Graph(Func<HttpRequestMessage, HttpResponseMessage> handler) =>
        new(new HttpClient(new StubHandler(handler)) { BaseAddress = new("https://graph.microsoft.com/v1.0/") }, new FixedToken(), (_, _) => Task.CompletedTask);
    private static HttpResponseMessage Json(HttpStatusCode status, string json) => new(status) { Content = new StringContent(json, Encoding.UTF8, "application/json") };

    private sealed class FixedToken : IWorkerTokenProvider { public Task<string> GetAppTokenAsync(CancellationToken cancellationToken) => Task.FromResult("synthetic-token"); }
    private sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> handler) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => Task.FromResult(handler(request));
    }
    private sealed class FakeInventory(PlacesInventory value) : IPlacesInventoryReader { public Task<PlacesInventory> ReadAsync(CancellationToken cancellationToken) => Task.FromResult(value); }

    private sealed class FakePlaces : IPlacesWriteClient
    {
        private readonly List<PlaceRecord> items = []; private int reads;
        public int Calls, Creates; public Exception? CreateThrows; public int HideReadsFor; public string? ReadBackName; public string? LastParentGraphId;
        public void Add(PlaceType type, string id, string? stable, string name, string? parent = null) => items.Add(new(id, parent, type, name, null, null, null, "test", DateTimeOffset.UtcNow, stable));
        public Task<IReadOnlyList<PlaceRecord>> ListAsync(PlaceType type, CancellationToken cancellationToken) { Interlocked.Increment(ref Calls); lock (items) return Task.FromResult<IReadOnlyList<PlaceRecord>>(items.Where(i => i.Type == type).ToArray()); }
        public Task<PlaceRecord?> GetAsync(string graphId, CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref Calls);
            if (Interlocked.Increment(ref reads) <= HideReadsFor) return Task.FromResult<PlaceRecord?>(null);
            lock (items) { var found = items.FirstOrDefault(i => i.Id == graphId); return Task.FromResult(found is null || ReadBackName is null ? found : found with { DisplayName = ReadBackName }); }
        }
        public Task<PlaceRecord> CreateAsync(PlacesWriteSpec spec, string parentGraphId, CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref Calls); Interlocked.Increment(ref Creates); LastParentGraphId = parentGraphId;
            if (CreateThrows is not null) throw CreateThrows;
            var created = new PlaceRecord(Guid.NewGuid().ToString("N"), PlacesWriteSpec.RequiredParent(spec.Kind) is null ? null : parentGraphId, spec.Kind, spec.DisplayName, null, null, null, "test", DateTimeOffset.UtcNow, Guid.NewGuid().ToString("N"));
            lock (items) items.Add(created); return Task.FromResult(created);
        }
        public Task UpdateAsync(string graphId, PlacesWriteSpec spec, CancellationToken cancellationToken)
        {
            Interlocked.Increment(ref Calls);
            lock (items) { var i = items.FindIndex(x => x.Id == graphId); if (i >= 0) items[i] = items[i] with { DisplayName = spec.DisplayName }; }
            return Task.CompletedTask;
        }
    }
}
