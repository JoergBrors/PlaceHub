using System.Text.RegularExpressions;

namespace PlaceHub.Core;

public enum ParkingMailboxType { Equipment, Room }
public enum ExchangeOperation { DiscoverResourceMailbox, ImportExistingParkingResource, CreateParkingResource, UpdateParkingResource, ConfigureBookingPolicy, DisableParkingResource, VerifyProvisioningState, ReconcileParkingResource }

/// <summary>Typed Exchange payload. Contains only values; command names and parameter names are fixed in <see cref="ExchangeCommandPlanner"/>.</summary>
public sealed record ExchangeSpec(string MailboxAddress, string? Name = null, string? Alias = null, string? DisplayName = null, ParkingMailboxType? MailboxType = null, string? PolicyTemplateId = null)
{
    private static readonly Regex Address = new(@"^[a-z0-9][a-z0-9._-]{0,63}@[a-z0-9][a-z0-9.-]{0,120}\.[a-z]{2,24}$", RegexOptions.Compiled | RegexOptions.CultureInvariant);
    private static readonly Regex NamePattern = new(@"^[A-Za-z0-9][A-Za-z0-9 _-]{1,63}$", RegexOptions.Compiled | RegexOptions.CultureInvariant);
    private static readonly Regex AliasPattern = new(@"^[a-z0-9][a-z0-9-]{1,63}$", RegexOptions.Compiled | RegexOptions.CultureInvariant);
    private static readonly Regex DisplayPattern = new(@"^[\p{L}\p{N}][\p{L}\p{N} _.()/-]{0,127}$", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    public static ExchangeOperation? MapOperation(OperationKind operation) => operation switch
    {
        OperationKind.Create => ExchangeOperation.CreateParkingResource,
        OperationKind.Update => ExchangeOperation.UpdateParkingResource,
        OperationKind.ChangeBookingPolicy => ExchangeOperation.ConfigureBookingPolicy,
        OperationKind.Disable => ExchangeOperation.DisableParkingResource,
        OperationKind.Reconcile => ExchangeOperation.ReconcileParkingResource,
        _ => null
    };

    public static bool IsValidAddress(string? value) => value is not null && Address.IsMatch(value);

    public void Validate(OperationKind operation)
    {
        if (MapOperation(operation) is not { } mapped) throw new ValidationException("EXCHANGE_OPERATION_NOT_ALLOWED");
        if (!IsValidAddress(MailboxAddress)) throw new ValidationException("MAILBOX_ADDRESS_INVALID");
        switch (mapped)
        {
            case ExchangeOperation.CreateParkingResource:
                if (Name is null || !NamePattern.IsMatch(Name)) throw new ValidationException("MAILBOX_NAME_INVALID");
                if (Alias is null || !AliasPattern.IsMatch(Alias)) throw new ValidationException("MAILBOX_ALIAS_INVALID");
                if (DisplayName is null || !DisplayPattern.IsMatch(DisplayName)) throw new ValidationException("MAILBOX_DISPLAY_NAME_INVALID");
                if (MailboxType is null || !Enum.IsDefined(MailboxType.Value)) throw new ValidationException("MAILBOX_TYPE_REQUIRED");
                break;
            case ExchangeOperation.UpdateParkingResource:
                if (DisplayName is null || !DisplayPattern.IsMatch(DisplayName)) throw new ValidationException("MAILBOX_DISPLAY_NAME_INVALID");
                break;
            case ExchangeOperation.ConfigureBookingPolicy:
                if (PolicyTemplateId is null || !ExchangeCommandPlanner.PolicyTemplates.ContainsKey(PolicyTemplateId)) throw new ValidationException("POLICY_TEMPLATE_NOT_ALLOWED");
                break;
        }
    }
}

public sealed record ExchangeProvisioningOptions
{
    /// <summary>Master switch; the worker refuses to run while false.</summary>
    public bool Enabled { get; init; }
    /// <summary>Organization-wide New-Mailbox residual risk; separate Project Owner and security approval (ADR-006).</summary>
    public bool MailboxCreationApproved { get; init; }
    /// <summary>Equipment or Room: undecided until ADR-006 is accepted; creation is refused while null.</summary>
    public ParkingMailboxType? ApprovedMailboxType { get; init; }
    public IReadOnlyList<string> ApprovedSmtpDomains { get; init; } = [];
    public string NamePrefix { get; init; } = "PH-PARK-";
    public int ReadBackAttempts { get; init; } = 3;
    public TimeSpan ReadBackDelay { get; init; } = TimeSpan.FromSeconds(10);
}

/// <summary>One fixed command. A null parameter value denotes a switch.</summary>
public sealed record ExchangeCommand(string Cmdlet, IReadOnlyList<KeyValuePair<string, string?>> Parameters, bool Mutating);

public sealed record ExchangeResult(IReadOnlyDictionary<string, string?> Properties, bool Found = true)
{
    public static ExchangeResult NotFound { get; } = new(new Dictionary<string, string?>(), false);
}

public interface IExchangeCommandRunner { Task<ExchangeResult> RunAsync(ExchangeCommand command, CancellationToken cancellationToken); }

public sealed class UnavailableExchangeCommandRunner : IExchangeCommandRunner
{
    public Task<ExchangeResult> RunAsync(ExchangeCommand command, CancellationToken cancellationToken) => throw new IntegrationConfigurationException("EXCHANGE_RUNNER_UNAVAILABLE");
}

public static class ExchangeCommandPlanner
{
    // Proposed templates built only from documented Set-CalendarProcessing parameters; they need Project Owner approval before live use (ADR-006).
    public static readonly IReadOnlyDictionary<string, IReadOnlyDictionary<string, string>> PolicyTemplates = new Dictionary<string, IReadOnlyDictionary<string, string>>
    {
        ["standard"] = new Dictionary<string, string> { ["AutomateProcessing"] = "AutoAccept", ["AllowConflicts"] = "False", ["BookingWindowInDays"] = "14", ["MaximumDurationInMinutes"] = "1440", ["AllowRecurringMeetings"] = "False" },
        ["restricted"] = new Dictionary<string, string> { ["AutomateProcessing"] = "AutoAccept", ["AllowConflicts"] = "False", ["BookingWindowInDays"] = "7", ["MaximumDurationInMinutes"] = "600", ["AllowRecurringMeetings"] = "False" }
    };

    /// <summary>Exact cmdlets and parameters the worker may ever use. No Remove-*, no delegation, forwarding or type-conversion parameters.</summary>
    public static readonly IReadOnlyDictionary<string, IReadOnlySet<string>> Allowlist = new Dictionary<string, IReadOnlySet<string>>(StringComparer.OrdinalIgnoreCase)
    {
        ["Get-EXOMailbox"] = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Identity", "Properties" },
        ["Get-CalendarProcessing"] = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Identity" },
        ["New-Mailbox"] = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Equipment", "Room", "Name", "Alias", "DisplayName", "PrimarySmtpAddress" },
        ["Set-Mailbox"] = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Identity", "DisplayName" },
        ["Set-CalendarProcessing"] = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "Identity", "AutomateProcessing", "AllowConflicts", "BookingWindowInDays", "MaximumDurationInMinutes", "AllowRecurringMeetings" }
    };

    private static readonly string[] ReadProperties = ["DisplayName", "PrimarySmtpAddress", "RecipientTypeDetails", "Alias"];
    private static KeyValuePair<string, string?> P(string name, string? value) => new(name, value);

    public static ExchangeCommand ReadMailbox(string address) => new("Get-EXOMailbox", [P("Identity", address), P("Properties", string.Join(",", ReadProperties))], false);
    public static ExchangeCommand ReadPolicy(string address) => new("Get-CalendarProcessing", [P("Identity", address)], false);

    public static ExchangeCommand Create(ExchangeSpec spec, ParkingMailboxType type) => new("New-Mailbox",
        [P(type == ParkingMailboxType.Equipment ? "Equipment" : "Room", null), P("Name", spec.Name), P("Alias", spec.Alias), P("DisplayName", spec.DisplayName), P("PrimarySmtpAddress", spec.MailboxAddress)], true);

    public static ExchangeCommand Update(ExchangeSpec spec) => new("Set-Mailbox", [P("Identity", spec.MailboxAddress), P("DisplayName", spec.DisplayName)], true);

    public static ExchangeCommand ConfigurePolicy(ExchangeSpec spec) => new("Set-CalendarProcessing",
        [P("Identity", spec.MailboxAddress), .. PolicyTemplates[spec.PolicyTemplateId!].Select(kv => P(kv.Key, kv.Value))], true);

    /// <summary>Defense in depth: any command, whoever built it, must be on the allowlist before it reaches a runner.</summary>
    public static void Assert(ExchangeCommand command)
    {
        if (!Allowlist.TryGetValue(command.Cmdlet, out var allowed)) throw new ValidationException("EXCHANGE_CMDLET_NOT_ALLOWLISTED");
        foreach (var (name, value) in command.Parameters)
        {
            if (!allowed.Contains(name)) throw new ValidationException("EXCHANGE_PARAMETER_NOT_ALLOWLISTED");
            if (value is not null && (value.Length > 512 || value.Any(c => char.IsControl(c) || c is ';' or '|' or '`' or '$' or '"' or '\'' or '&' or '<' or '>' or '{' or '}')))
                throw new ValidationException("EXCHANGE_PARAMETER_VALUE_REJECTED");
        }
        if (command.Cmdlet is "New-Mailbox" && command.Parameters.Count(p => p.Key is "Equipment" or "Room") != 1) throw new ValidationException("MAILBOX_TYPE_REQUIRED");
    }
}

/// <summary>Wraps a runner so that nothing outside the allowlist can reach it, regardless of the caller.</summary>
public sealed class GuardedExchangeRunner(IExchangeCommandRunner inner) : IExchangeCommandRunner
{
    public Task<ExchangeResult> RunAsync(ExchangeCommand command, CancellationToken cancellationToken) { ExchangeCommandPlanner.Assert(command); return inner.RunAsync(command, cancellationToken); }
}

/// <summary>
/// Executes approved parking-resource requests through the fixed command set. Refuses unless enabled, revalidates the approval itself,
/// never retries an ambiguous mailbox creation and verifies every change by reading it back. Mailbox deletion does not exist here.
/// </summary>
public sealed class ExchangeProvisioningWorker(IExchangeCommandRunner runner, ExchangeProvisioningOptions options, Func<TimeSpan, CancellationToken, Task>? delay = null) : IProvisioningWorker
{
    private readonly IExchangeCommandRunner guarded = new GuardedExchangeRunner(runner);
    private readonly Func<TimeSpan, CancellationToken, Task> wait = delay ?? Task.Delay;

    public async Task<ProvisioningResult> ExecuteAsync(AdministrationRequest request, CancellationToken cancellationToken)
    {
        request.VerifyApprovalIntegrity();
        if (!options.Enabled) throw new WorkflowException("EXCHANGE_PROVISIONING_NOT_ACTIVATED");
        var spec = request.Specification.Exchange;
        if (request.Specification.ResourceKind != ResourceKind.ParkingResource || spec is null) return new(RequestState.Failed, "OPERATION_NOT_ALLOWLISTED");
        var operation = request.Specification.Operation;
        try { spec.Validate(operation); }
        catch (ValidationException ex) { return new(RequestState.Failed, ex.Code); }
        var gate = CheckGates(spec, operation);
        if (gate is not null) return new(RequestState.Failed, gate);
        try
        {
            return operation switch
            {
                OperationKind.Create => await CreateAsync(spec, cancellationToken),
                OperationKind.Update => await UpdateAsync(spec, cancellationToken),
                OperationKind.ChangeBookingPolicy => await ConfigureAsync(spec, cancellationToken),
                OperationKind.Reconcile => await VerifyAsync(spec, cancellationToken),
                _ => new(RequestState.Failed, "DISABLE_SEMANTICS_NOT_DECIDED")
            };
        }
        catch (AmbiguousOutcomeException ex) { return new(RequestState.RequiresReconciliation, ex.Code); }
        catch (IntegrationException ex) { return new(RequestState.Failed, ex.Code); }
    }

    private string? CheckGates(ExchangeSpec spec, OperationKind operation)
    {
        if (!options.ApprovedSmtpDomains.Any(d => spec.MailboxAddress.EndsWith("@" + d, StringComparison.OrdinalIgnoreCase))) return "SMTP_DOMAIN_NOT_APPROVED";
        if (operation == OperationKind.Disable) return "DISABLE_SEMANTICS_NOT_DECIDED";
        if (operation != OperationKind.Create) return null;
        if (!options.MailboxCreationApproved) return "MAILBOX_CREATE_NOT_APPROVED";
        if (options.ApprovedMailboxType is null) return "MAILBOX_TYPE_NOT_DECIDED";
        if (spec.MailboxType != options.ApprovedMailboxType) return "MAILBOX_TYPE_NOT_APPROVED";
        if (!(spec.Name ?? "").StartsWith(options.NamePrefix, StringComparison.Ordinal)) return "MAILBOX_NAME_PREFIX_REQUIRED";
        return null;
    }

    private async Task<ProvisioningResult> CreateAsync(ExchangeSpec spec, CancellationToken cancellationToken)
    {
        var existing = await guarded.RunAsync(ExchangeCommandPlanner.ReadMailbox(spec.MailboxAddress), cancellationToken);
        if (existing.Found) return new(RequestState.RequiresReconciliation, "MAILBOX_ALREADY_EXISTS");
        await guarded.RunAsync(ExchangeCommandPlanner.Create(spec, spec.MailboxType!.Value), cancellationToken);
        for (var attempt = 1; attempt <= Math.Max(1, options.ReadBackAttempts); attempt++)
        {
            var read = await guarded.RunAsync(ExchangeCommandPlanner.ReadMailbox(spec.MailboxAddress), cancellationToken);
            if (read.Found)
            {
                var expectedType = spec.MailboxType == ParkingMailboxType.Equipment ? "EquipmentMailbox" : "RoomMailbox";
                var ok = Equal(read, "RecipientTypeDetails", expectedType) && Equal(read, "DisplayName", spec.DisplayName!);
                return ok ? new(RequestState.Succeeded, "MAILBOX_CREATED_VERIFIED") : new(RequestState.RequiresReconciliation, "READ_AFTER_WRITE_MISMATCH");
            }
            if (attempt < options.ReadBackAttempts) await wait(options.ReadBackDelay, cancellationToken);
        }
        return new(RequestState.PendingPropagation, "MAILBOX_PENDING_PROPAGATION");
    }

    private async Task<ProvisioningResult> UpdateAsync(ExchangeSpec spec, CancellationToken cancellationToken)
    {
        if (!(await guarded.RunAsync(ExchangeCommandPlanner.ReadMailbox(spec.MailboxAddress), cancellationToken)).Found) return new(RequestState.Failed, "MAILBOX_NOT_FOUND");
        await guarded.RunAsync(ExchangeCommandPlanner.Update(spec), cancellationToken);
        var read = await guarded.RunAsync(ExchangeCommandPlanner.ReadMailbox(spec.MailboxAddress), cancellationToken);
        return read.Found && Equal(read, "DisplayName", spec.DisplayName!) ? new(RequestState.Succeeded, "MAILBOX_UPDATED_VERIFIED") : new(RequestState.PendingPropagation, "MAILBOX_UPDATE_PENDING_PROPAGATION");
    }

    private async Task<ProvisioningResult> ConfigureAsync(ExchangeSpec spec, CancellationToken cancellationToken)
    {
        if (!(await guarded.RunAsync(ExchangeCommandPlanner.ReadMailbox(spec.MailboxAddress), cancellationToken)).Found) return new(RequestState.Failed, "MAILBOX_NOT_FOUND");
        await guarded.RunAsync(ExchangeCommandPlanner.ConfigurePolicy(spec), cancellationToken);
        var read = await guarded.RunAsync(ExchangeCommandPlanner.ReadPolicy(spec.MailboxAddress), cancellationToken);
        var template = ExchangeCommandPlanner.PolicyTemplates[spec.PolicyTemplateId!];
        return template.All(kv => Equal(read, kv.Key, kv.Value)) ? new(RequestState.Succeeded, "BOOKING_POLICY_VERIFIED") : new(RequestState.RequiresReconciliation, "BOOKING_POLICY_MISMATCH");
    }

    private async Task<ProvisioningResult> VerifyAsync(ExchangeSpec spec, CancellationToken cancellationToken)
    {
        var read = await guarded.RunAsync(ExchangeCommandPlanner.ReadMailbox(spec.MailboxAddress), cancellationToken);
        if (!read.Found) return new(RequestState.RequiresReconciliation, "MAILBOX_NOT_FOUND");
        var type = read.Properties.GetValueOrDefault("RecipientTypeDetails");
        return type is "EquipmentMailbox" or "RoomMailbox" ? new(RequestState.Succeeded, "MAILBOX_STATE_VERIFIED") : new(RequestState.RequiresReconciliation, "MAILBOX_TYPE_UNEXPECTED");
    }

    private static bool Equal(ExchangeResult result, string key, string expected) =>
        result.Properties.TryGetValue(key, out var actual) && string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase);
}
