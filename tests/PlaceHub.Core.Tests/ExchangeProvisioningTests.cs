using PlaceHub.Core;
using Xunit;

namespace PlaceHub.Core.Tests;

public sealed class ExchangeProvisioningTests
{
    private const string Location = "BER";
    private const string Address = "ph-park-01@contoso.example";
    private static Actor Office() => new("office", PlaceHubRole.OfficeManager, new HashSet<string> { Location });
    private static Actor Admin() => new("admin", PlaceHubRole.SystemAdministrator, new HashSet<string> { Location });

    private static ExchangeSpec CreateSpec(ParkingMailboxType type = ParkingMailboxType.Equipment, string address = Address) =>
        new(address, "PH-PARK-01", "ph-park-01", "Parkplatz 01", type);

    private static AdministrationRequest Approved(OperationKind op, ExchangeSpec spec)
    {
        var request = new AdministrationRequest(ResourceSpecification.ForExchange(op, Location, spec.DisplayName ?? "Parkplatz 01", spec), Office(), Guid.NewGuid().ToString("N"), "cor");
        request.Submit(Office(), request.Version); request.Approve(Admin(), request.Version);
        return request;
    }

    private static ExchangeProvisioningOptions Options(bool enabled = true, bool create = true, ParkingMailboxType? type = ParkingMailboxType.Equipment, string[]? domains = null, int attempts = 3) =>
        new() { Enabled = enabled, MailboxCreationApproved = create, ApprovedMailboxType = type, ApprovedSmtpDomains = domains ?? ["contoso.example"], ReadBackAttempts = attempts, ReadBackDelay = TimeSpan.Zero };

    private static ExchangeProvisioningWorker Worker(FakeRunner runner, ExchangeProvisioningOptions? options = null) => new(runner, options ?? Options(), (_, _) => Task.CompletedTask);

    // ---- spec validation ---------------------------------------------------

    [Theory]
    [InlineData("a@b.example;calc")]
    [InlineData("a b@contoso.example")]
    [InlineData("a@contoso.example\nb")]
    [InlineData("a\"@contoso.example")]
    [InlineData("A@contoso.example")]
    [InlineData("a@contoso")]
    [InlineData("")]
    [InlineData("@contoso.example")]
    public void MailboxAddressMustBeCanonicalAndInjectionFree(string address) =>
        Assert.Equal("MAILBOX_ADDRESS_INVALID", Assert.Throws<ValidationException>(() => new ExchangeSpec(address).Validate(OperationKind.Reconcile)).Code);

    [Theory]
    [InlineData("x$(calc)", "ph-park-01", "Parkplatz", "MAILBOX_NAME_INVALID")]
    [InlineData("PH-PARK-01", "Bad Alias", "Parkplatz", "MAILBOX_ALIAS_INVALID")]
    [InlineData("PH-PARK-01", "ph-park-01", "Parkplatz; Remove-Mailbox", "MAILBOX_DISPLAY_NAME_INVALID")]
    [InlineData("PH-PARK-01", "ph-park-01", "", "MAILBOX_DISPLAY_NAME_INVALID")]
    public void CreateFieldsAreValidatedAgainstStrictPatterns(string name, string alias, string display, string code) =>
        Assert.Equal(code, Assert.Throws<ValidationException>(() => new ExchangeSpec(Address, name, alias, display, ParkingMailboxType.Equipment).Validate(OperationKind.Create)).Code);

    [Fact]
    public void CreateNeedsAMailboxTypeAndPolicyNeedsAKnownTemplate()
    {
        Assert.Equal("MAILBOX_TYPE_REQUIRED", Assert.Throws<ValidationException>(() => new ExchangeSpec(Address, "PH-PARK-01", "ph-park-01", "P").Validate(OperationKind.Create)).Code);
        Assert.Equal("POLICY_TEMPLATE_NOT_ALLOWED", Assert.Throws<ValidationException>(() => new ExchangeSpec(Address, PolicyTemplateId: "open").Validate(OperationKind.ChangeBookingPolicy)).Code);
        new ExchangeSpec(Address, PolicyTemplateId: "restricted").Validate(OperationKind.ChangeBookingPolicy);
    }

    [Fact]
    public void ChangeCapacityHasNoExchangeEquivalent() =>
        Assert.Equal("EXCHANGE_OPERATION_NOT_ALLOWED", Assert.Throws<ValidationException>(() => new ExchangeSpec(Address).Validate(OperationKind.ChangeCapacity)).Code);

    [Fact]
    public void RequestRejectsAnExchangePayloadOnTheWrongKind()
    {
        var bad = new ResourceSpecification(ResourceKind.DeskPool, OperationKind.Create, Location, "B", "1", "N", "Name", 5, null, Exchange: new ExchangeSpec(Address));
        Assert.Equal("EXCHANGE_PAYLOAD_MISMATCH", Assert.Throws<ValidationException>(() => new AdministrationRequest(bad, Office(), "k", "c")).Code);
    }

    // ---- fixed command set -------------------------------------------------

    [Fact]
    public void AllowlistContainsNoDeletionOrDisableCmdletAndNoDangerousParameters()
    {
        Assert.DoesNotContain(ExchangeCommandPlanner.Allowlist.Keys, c => c.StartsWith("Remove-", StringComparison.OrdinalIgnoreCase) || c.StartsWith("Disable-", StringComparison.OrdinalIgnoreCase) || c.StartsWith("Connect", StringComparison.OrdinalIgnoreCase) || c.StartsWith("Invoke", StringComparison.OrdinalIgnoreCase));
        var parameters = ExchangeCommandPlanner.Allowlist.Values.SelectMany(v => v).ToArray();
        foreach (var forbidden in new[] { "ForwardingAddress", "ForwardingSmtpAddress", "GrantSendOnBehalfTo", "LitigationHoldEnabled", "IgnoreDefaultScope", "ResourceDelegates", "AddOrganizerToSubject", "Type", "ConvertToShared" })
            Assert.DoesNotContain(forbidden, parameters, StringComparer.OrdinalIgnoreCase);
    }

    [Fact]
    public void EveryPlannedCommandPassesTheGuard()
    {
        var spec = CreateSpec();
        foreach (var command in new[] { ExchangeCommandPlanner.ReadMailbox(Address), ExchangeCommandPlanner.ReadPolicy(Address), ExchangeCommandPlanner.Create(spec, ParkingMailboxType.Equipment), ExchangeCommandPlanner.Create(spec, ParkingMailboxType.Room), ExchangeCommandPlanner.Update(spec), ExchangeCommandPlanner.ConfigurePolicy(new ExchangeSpec(Address, PolicyTemplateId: "standard")), ExchangeCommandPlanner.ConfigurePolicy(new ExchangeSpec(Address, PolicyTemplateId: "restricted")) })
            ExchangeCommandPlanner.Assert(command);
    }

    [Fact]
    public void CreateUsesExactlyOneTypeSwitch()
    {
        var equipment = ExchangeCommandPlanner.Create(CreateSpec(), ParkingMailboxType.Equipment);
        var room = ExchangeCommandPlanner.Create(CreateSpec(ParkingMailboxType.Room), ParkingMailboxType.Room);
        Assert.Contains(equipment.Parameters, p => p.Key == "Equipment" && p.Value is null); Assert.DoesNotContain(equipment.Parameters, p => p.Key == "Room");
        Assert.Contains(room.Parameters, p => p.Key == "Room" && p.Value is null); Assert.DoesNotContain(room.Parameters, p => p.Key == "Equipment");
        Assert.True(equipment.Mutating);
    }

    private static ExchangeCommand Cmd(string cmdlet, params (string, string?)[] p) => new(cmdlet, p.Select(x => new KeyValuePair<string, string?>(x.Item1, x.Item2)).ToArray(), true);

    [Theory]
    [InlineData("Remove-Mailbox", "Identity", "a@contoso.example", "EXCHANGE_CMDLET_NOT_ALLOWLISTED")]
    [InlineData("Invoke-Expression", "Command", "calc", "EXCHANGE_CMDLET_NOT_ALLOWLISTED")]
    [InlineData("Set-Mailbox", "ForwardingAddress", "evil@x.example", "EXCHANGE_PARAMETER_NOT_ALLOWLISTED")]
    [InlineData("Set-CalendarProcessing", "IgnoreDefaultScope", null, "EXCHANGE_PARAMETER_NOT_ALLOWLISTED")]
    [InlineData("Set-Mailbox", "DisplayName", "x; Remove-Mailbox", "EXCHANGE_PARAMETER_VALUE_REJECTED")]
    [InlineData("Set-Mailbox", "DisplayName", "$(calc)", "EXCHANGE_PARAMETER_VALUE_REJECTED")]
    [InlineData("Set-Mailbox", "DisplayName", "a`nb", "EXCHANGE_PARAMETER_VALUE_REJECTED")]
    [InlineData("Set-Mailbox", "DisplayName", "a|b", "EXCHANGE_PARAMETER_VALUE_REJECTED")]
    public void TheGuardRejectsAnythingOutsideTheAllowlist(string cmdlet, string parameter, string? value, string code) =>
        Assert.Equal(code, Assert.Throws<ValidationException>(() => ExchangeCommandPlanner.Assert(Cmd(cmdlet, (parameter, value)))).Code);

    [Fact]
    public void NewMailboxWithBothOrNoTypeSwitchIsRejected()
    {
        Assert.Throws<ValidationException>(() => ExchangeCommandPlanner.Assert(Cmd("New-Mailbox", ("Name", "PH-1"))));
        Assert.Throws<ValidationException>(() => ExchangeCommandPlanner.Assert(Cmd("New-Mailbox", ("Equipment", null), ("Room", null), ("Name", "PH-1"))));
    }

    [Fact]
    public async Task GuardedRunnerNeverForwardsADisallowedCommand()
    {
        var inner = new FakeRunner();
        await Assert.ThrowsAsync<ValidationException>(() => new GuardedExchangeRunner(inner).RunAsync(Cmd("Remove-Mailbox", ("Identity", "a@contoso.example")), default));
        Assert.Empty(inner.Commands);
    }

    [Fact]
    public void PolicyTemplatesUseOnlyAllowlistedCalendarProcessingParameters()
    {
        var allowed = ExchangeCommandPlanner.Allowlist["Set-CalendarProcessing"];
        foreach (var template in ExchangeCommandPlanner.PolicyTemplates.Values) foreach (var key in template.Keys) Assert.Contains(key, allowed);
    }

    // ---- worker gates ------------------------------------------------------

    [Fact]
    public async Task WorkerRefusesWhileDisabledAndRunsNothing()
    {
        var runner = new FakeRunner();
        var ex = await Assert.ThrowsAsync<WorkflowException>(() => Worker(runner, Options(enabled: false)).ExecuteAsync(Approved(OperationKind.Create, CreateSpec()), default));
        Assert.Equal("EXCHANGE_PROVISIONING_NOT_ACTIVATED", ex.Code); Assert.Empty(runner.Commands);
    }

    [Fact]
    public async Task WorkerRejectsAnUnapprovedRequest()
    {
        var request = new AdministrationRequest(ResourceSpecification.ForExchange(OperationKind.Create, Location, "P", CreateSpec()), Office(), "k", "c");
        var runner = new FakeRunner();
        Assert.Equal("APPROVAL_INTEGRITY_FAILED", (await Assert.ThrowsAsync<WorkflowException>(() => Worker(runner).ExecuteAsync(request, default))).Code);
        Assert.Empty(runner.Commands);
    }

    [Theory]
    [InlineData(false, ParkingMailboxType.Equipment, "contoso.example", "MAILBOX_CREATE_NOT_APPROVED")]
    [InlineData(true, null, "contoso.example", "MAILBOX_TYPE_NOT_DECIDED")]
    [InlineData(true, ParkingMailboxType.Room, "contoso.example", "MAILBOX_TYPE_NOT_APPROVED")]
    [InlineData(true, ParkingMailboxType.Equipment, "other.example", "SMTP_DOMAIN_NOT_APPROVED")]
    public async Task MailboxCreationStaysBehindItsGates(bool approved, ParkingMailboxType? type, string domain, string code)
    {
        var runner = new FakeRunner();
        var result = await Worker(runner, Options(create: approved, type: type, domains: [domain])).ExecuteAsync(Approved(OperationKind.Create, CreateSpec()), default);
        Assert.Equal((RequestState.Failed, code), (result.State, result.OutcomeCode)); Assert.Empty(runner.Commands);
    }

    [Fact]
    public async Task MailboxNameMustCarryTheApprovedPrefix()
    {
        var runner = new FakeRunner();
        var spec = new ExchangeSpec(Address, "Other-01", "other-01", "Parkplatz", ParkingMailboxType.Equipment);
        Assert.Equal("MAILBOX_NAME_PREFIX_REQUIRED", (await Worker(runner).ExecuteAsync(Approved(OperationKind.Create, spec), default)).OutcomeCode); Assert.Empty(runner.Commands);
    }

    [Fact]
    public async Task DisableIsBlockedUntilItsSemanticsAreDecidedAndNothingIsDeleted()
    {
        var runner = new FakeRunner();
        var result = await Worker(runner).ExecuteAsync(Approved(OperationKind.Disable, new ExchangeSpec(Address)), default);
        Assert.Equal("DISABLE_SEMANTICS_NOT_DECIDED", result.OutcomeCode); Assert.Empty(runner.Commands);
    }

    // ---- create ------------------------------------------------------------

    [Fact]
    public async Task CreateChecksForAnExistingMailboxFirstAndNeverDuplicates()
    {
        var runner = new FakeRunner(); runner.Mailboxes[Address] = new() { ["RecipientTypeDetails"] = "EquipmentMailbox", ["DisplayName"] = "Parkplatz 01" };
        var result = await Worker(runner).ExecuteAsync(Approved(OperationKind.Create, CreateSpec()), default);
        Assert.Equal((RequestState.RequiresReconciliation, "MAILBOX_ALREADY_EXISTS"), (result.State, result.OutcomeCode));
        Assert.DoesNotContain(runner.Commands, c => c.Cmdlet == "New-Mailbox");
    }

    [Fact]
    public async Task CreateIsVerifiedByReadBackOfTypeAndName()
    {
        var runner = new FakeRunner();
        var result = await Worker(runner).ExecuteAsync(Approved(OperationKind.Create, CreateSpec()), default);
        Assert.Equal((RequestState.Succeeded, "MAILBOX_CREATED_VERIFIED"), (result.State, result.OutcomeCode));
        Assert.Equal(["Get-EXOMailbox", "New-Mailbox", "Get-EXOMailbox"], runner.Commands.Select(c => c.Cmdlet).ToArray());
    }

    [Fact]
    public async Task AmbiguousCreateGoesToReconciliationAndIsNotRetried()
    {
        var runner = new FakeRunner { CreateThrows = new AmbiguousOutcomeException("WRITE_OUTCOME_UNKNOWN") };
        var result = await Worker(runner).ExecuteAsync(Approved(OperationKind.Create, CreateSpec()), default);
        Assert.Equal((RequestState.RequiresReconciliation, "WRITE_OUTCOME_UNKNOWN"), (result.State, result.OutcomeCode));
        Assert.Equal(1, runner.Commands.Count(c => c.Cmdlet == "New-Mailbox"));
    }

    [Fact]
    public async Task DelayedVisibilityIsRetriedBoundedThenReportedAsPending()
    {
        var delayed = new FakeRunner { HideReadsAfterCreate = 2 };
        Assert.Equal(RequestState.Succeeded, (await Worker(delayed).ExecuteAsync(Approved(OperationKind.Create, CreateSpec()), default)).State);
        var never = new FakeRunner { HideReadsAfterCreate = int.MaxValue };
        var result = await Worker(never).ExecuteAsync(Approved(OperationKind.Create, CreateSpec()), default);
        Assert.Equal((RequestState.PendingPropagation, "MAILBOX_PENDING_PROPAGATION"), (result.State, result.OutcomeCode));
        Assert.Equal(1, never.Commands.Count(c => c.Cmdlet == "New-Mailbox"));
    }

    [Fact]
    public async Task ReadBackWithAnUnexpectedMailboxTypeRequiresReconciliation()
    {
        var runner = new FakeRunner { CreatedTypeOverride = "UserMailbox" };
        Assert.Equal("READ_AFTER_WRITE_MISMATCH", (await Worker(runner).ExecuteAsync(Approved(OperationKind.Create, CreateSpec()), default)).OutcomeCode);
    }

    [Fact]
    public async Task MissingRunnerFailsSafelyWithoutAnyCommand()
    {
        var result = await new ExchangeProvisioningWorker(new UnavailableExchangeCommandRunner(), Options(), (_, _) => Task.CompletedTask).ExecuteAsync(Approved(OperationKind.Create, CreateSpec()), default);
        Assert.Equal((RequestState.Failed, "EXCHANGE_RUNNER_UNAVAILABLE"), (result.State, result.OutcomeCode));
    }

    // ---- update / policy / verify ------------------------------------------

    [Fact]
    public async Task UpdateRequiresAnExistingMailboxAndReadsBack()
    {
        var runner = new FakeRunner();
        var spec = new ExchangeSpec(Address, DisplayName: "Neuer Name");
        Assert.Equal("MAILBOX_NOT_FOUND", (await Worker(runner).ExecuteAsync(Approved(OperationKind.Update, spec), default)).OutcomeCode);
        runner.Mailboxes[Address] = new() { ["RecipientTypeDetails"] = "EquipmentMailbox", ["DisplayName"] = "Alt" };
        var ok = await Worker(runner).ExecuteAsync(Approved(OperationKind.Update, spec), default);
        Assert.Equal((RequestState.Succeeded, "MAILBOX_UPDATED_VERIFIED"), (ok.State, ok.OutcomeCode));
    }

    [Theory]
    [InlineData("standard")]
    [InlineData("restricted")]
    public async Task BookingPolicyIsAppliedFromATemplateAndVerified(string template)
    {
        var runner = new FakeRunner(); runner.Mailboxes[Address] = new() { ["RecipientTypeDetails"] = "EquipmentMailbox" };
        var result = await Worker(runner).ExecuteAsync(Approved(OperationKind.ChangeBookingPolicy, new ExchangeSpec(Address, PolicyTemplateId: template)), default);
        Assert.Equal((RequestState.Succeeded, "BOOKING_POLICY_VERIFIED"), (result.State, result.OutcomeCode));
        Assert.Equal(["Get-EXOMailbox", "Set-CalendarProcessing", "Get-CalendarProcessing"], runner.Commands.Select(c => c.Cmdlet).ToArray());
    }

    [Fact]
    public async Task BookingPolicyMismatchAfterWriteRequiresReconciliation()
    {
        var runner = new FakeRunner { IgnorePolicyWrites = true }; runner.Mailboxes[Address] = new() { ["RecipientTypeDetails"] = "EquipmentMailbox" };
        Assert.Equal("BOOKING_POLICY_MISMATCH", (await Worker(runner).ExecuteAsync(Approved(OperationKind.ChangeBookingPolicy, new ExchangeSpec(Address, PolicyTemplateId: "standard")), default)).OutcomeCode);
    }

    [Theory]
    [InlineData("EquipmentMailbox", RequestState.Succeeded, "MAILBOX_STATE_VERIFIED")]
    [InlineData("RoomMailbox", RequestState.Succeeded, "MAILBOX_STATE_VERIFIED")]
    [InlineData("UserMailbox", RequestState.RequiresReconciliation, "MAILBOX_TYPE_UNEXPECTED")]
    public async Task ReconcileIsReadOnlyAndClassifiesTheMailbox(string type, RequestState state, string code)
    {
        var runner = new FakeRunner(); runner.Mailboxes[Address] = new() { ["RecipientTypeDetails"] = type };
        var result = await Worker(runner).ExecuteAsync(Approved(OperationKind.Reconcile, new ExchangeSpec(Address)), default);
        Assert.Equal((state, code), (result.State, result.OutcomeCode));
        Assert.All(runner.Commands, c => Assert.False(c.Mutating));
    }

    [Fact]
    public async Task ReconcileOfAMissingMailboxRequiresReconciliation()
    {
        var result = await Worker(new FakeRunner()).ExecuteAsync(Approved(OperationKind.Reconcile, new ExchangeSpec(Address)), default);
        Assert.Equal((RequestState.RequiresReconciliation, "MAILBOX_NOT_FOUND"), (result.State, result.OutcomeCode));
    }

    [Fact]
    public void ExchangeRequestsAreSubjectToFourEyes()
    {
        var admin = Admin();
        var request = new AdministrationRequest(ResourceSpecification.ForExchange(OperationKind.Create, Location, "P", CreateSpec()), admin, "k", "c");
        request.Submit(admin, request.Version);
        Assert.Equal("SELF_APPROVAL_DENIED", Assert.Throws<AuthorizationException>(() => request.Approve(admin, request.Version)).Code);
    }

    private sealed class FakeRunner : IExchangeCommandRunner
    {
        public readonly List<ExchangeCommand> Commands = [];
        public readonly Dictionary<string, Dictionary<string, string?>> Mailboxes = new(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, Dictionary<string, string?>> policies = new(StringComparer.OrdinalIgnoreCase);
        public Exception? CreateThrows; public int HideReadsAfterCreate; public string? CreatedTypeOverride; public bool IgnorePolicyWrites;
        private (string Address, Dictionary<string, string?> Props)? pending; private int hidden;

        public Task<ExchangeResult> RunAsync(ExchangeCommand command, CancellationToken cancellationToken)
        {
            Commands.Add(command);
            string P(string name) => command.Parameters.First(x => x.Key == name).Value ?? "";
            switch (command.Cmdlet)
            {
                case "Get-EXOMailbox":
                    if (pending is { } p && string.Equals(p.Address, P("Identity"), StringComparison.OrdinalIgnoreCase) && !Mailboxes.ContainsKey(p.Address))
                    {
                        if (hidden < HideReadsAfterCreate) { hidden++; return Task.FromResult(ExchangeResult.NotFound); }
                        Mailboxes[p.Address] = p.Props;
                    }
                    return Task.FromResult(Mailboxes.TryGetValue(P("Identity"), out var props) ? new ExchangeResult(props) : ExchangeResult.NotFound);
                case "New-Mailbox":
                    if (CreateThrows is not null) throw CreateThrows;
                    var type = CreatedTypeOverride ?? (command.Parameters.Any(x => x.Key == "Equipment") ? "EquipmentMailbox" : "RoomMailbox");
                    pending = (P("PrimarySmtpAddress"), new() { ["RecipientTypeDetails"] = type, ["DisplayName"] = P("DisplayName") });
                    return Task.FromResult(new ExchangeResult(new Dictionary<string, string?>()));
                case "Set-Mailbox":
                    if (Mailboxes.TryGetValue(P("Identity"), out var m)) m["DisplayName"] = P("DisplayName");
                    return Task.FromResult(new ExchangeResult(new Dictionary<string, string?>()));
                case "Set-CalendarProcessing":
                    if (!IgnorePolicyWrites) policies[P("Identity")] = command.Parameters.Where(x => x.Key != "Identity").ToDictionary(x => x.Key, x => x.Value);
                    return Task.FromResult(new ExchangeResult(new Dictionary<string, string?>()));
                case "Get-CalendarProcessing":
                    return Task.FromResult(new ExchangeResult(policies.GetValueOrDefault(P("Identity")) ?? new Dictionary<string, string?>()));
            }
            throw new InvalidOperationException("unexpected cmdlet");
        }
    }
}
