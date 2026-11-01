static bool Enabled(string name) =>
    bool.TryParse(Environment.GetEnvironmentVariable(name), out var value) && value;

var status = !Enabled("Worker__Enabled")
    ? "WORKER_DISABLED"
    : !Enabled("Worker__KeyVaultNetworkPathVerified")
        ? "NETWORK_PATH_UNAVAILABLE"
        : !Enabled("Worker__CredentialBootstrapVerified")
            ? "CREDENTIAL_BOOTSTRAP_REQUIRED"
            : "PRIVILEGED_EXECUTION_NOT_ACTIVATED";

Console.WriteLine(status);
await File.WriteAllTextAsync("/tmp/placehub-worker-boundary-ready", "BOUNDARY_READY");

using var stopping = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) =>
{
    eventArgs.Cancel = true;
    stopping.Cancel();
};

try
{
    await Task.Delay(Timeout.InfiniteTimeSpan, stopping.Token);
}
catch (OperationCanceledException) when (stopping.IsCancellationRequested)
{
    // Normal container shutdown.
}
