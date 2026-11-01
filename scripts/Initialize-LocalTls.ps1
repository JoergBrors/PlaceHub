#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string] $OutputDirectory,
    [switch] $Trust
)

$ErrorActionPreference = 'Stop'

if (-not $PSBoundParameters.ContainsKey('OutputDirectory')) {
    $envFile = Join-Path (Get-Location) '.env'
    if (Test-Path -LiteralPath $envFile) {
        $configuredLine = Get-Content -LiteralPath $envFile |
            Where-Object { $_ -match '^\s*PLACEHUB_TLS_DIRECTORY\s*=' } |
            Select-Object -Last 1
        if ($configuredLine) {
            $OutputDirectory = ($configuredLine -split '=', 2)[1].Trim().Trim('"').Trim("'")
        }
    }

    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PlaceHub/tls'
    }
}

if (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
    $OutputDirectory = Join-Path (Get-Location) $OutputDirectory
}

$certificatePath = Join-Path $OutputDirectory 'tls.crt'
$keyPath = Join-Path $OutputDirectory 'tls.key'

if ((Test-Path -LiteralPath $certificatePath) -or (Test-Path -LiteralPath $keyPath)) {
    throw 'LOCAL_TLS_ALREADY_EXISTS'
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'DOTNET_NOT_FOUND'
}

if (-not $PSCmdlet.ShouldProcess('configured TLS directory', 'create local HTTPS development certificate')) {
    Write-Output 'LOCAL_TLS_PREVIEW_OK'
    return
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

if ($Trust) {
    & dotnet dev-certs https --trust
    if ($LASTEXITCODE -ne 0) { throw 'LOCAL_TLS_TRUST_FAILED' }
}

& dotnet dev-certs https --export-path $certificatePath --format PEM --no-password
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $certificatePath) -or -not (Test-Path -LiteralPath $keyPath)) {
    throw 'LOCAL_TLS_EXPORT_FAILED'
}

if (-not $IsWindows) {
    & chmod 600 $certificatePath $keyPath
    if ($LASTEXITCODE -ne 0) { throw 'LOCAL_TLS_PERMISSION_FAILED' }
}

Write-Output 'LOCAL_TLS_READY'
Write-Output 'PLACEHUB_TLS_DIRECTORY_READY'
