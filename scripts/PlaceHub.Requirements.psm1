Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Numeric exit codes of Invoke-PlaceHub-Requirements.ps1.
$script:ExitCodes = [ordered]@{
    SUCCESS = 0
    PREREQUISITE_MISSING = 10
    AUTHENTICATION_REQUIRED = 20
    APPROVAL_REQUIRED = 30
    VALIDATION_FAILED = 40
    SECURITY_BLOCKED = 50
    EXECUTION_FAILED = 60
}

$script:ActionClasses = @('READ_ONLY', 'LOCAL_MUTATION', 'TENANT_MUTATION', 'PRIVILEGED_MUTATION', 'DESTRUCTIVE')
$script:ToolAllowlist = @('az', 'gh', 'git', 'docker', 'terraform', 'dotnet', 'pwsh', 'python')

function Get-RequirementsExitCodes { $script:ExitCodes }
function Get-RequirementsActionClasses { $script:ActionClasses }

class RequirementsException : System.Exception {
    [string]$ExitName
    RequirementsException([string]$exitName, [string]$message) : base($message) { $this.ExitName = $exitName }
}

function Stop-Requirements {
    param([Parameter(Mandatory)][ValidateSet('PREREQUISITE_MISSING','AUTHENTICATION_REQUIRED','APPROVAL_REQUIRED','VALIDATION_FAILED','SECURITY_BLOCKED','EXECUTION_FAILED')][string]$Exit, [Parameter(Mandatory)][string]$Message)
    throw [RequirementsException]::new($Exit, $Message)
}

# --- redaction ---------------------------------------------------------------

function Protect-Text {
    [CmdletBinding()] param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $out = $Text
    $out = [regex]::Replace($out, '-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(-----END [A-Z ]*PRIVATE KEY-----|$)', '[REDACTED_PRIVATE_KEY]')
    $out = [regex]::Replace($out, 'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}(\.[A-Za-z0-9_-]*)?', '[REDACTED_TOKEN]')
    $out = [regex]::Replace($out, '(?i)\b(access_token|refresh_token|id_token|client_secret|password|passwd|pwd|secret|accountkey|sharedaccesskey|pfxpassword)\b(["'']?\s*[:=]\s*)(["'']?)[^\s"'',;]+', '$1$2$3[REDACTED]')
    $out = [regex]::Replace($out, '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{8,}', 'Bearer [REDACTED]')
    $out = [regex]::Replace($out, '\bgh[pousr]_[A-Za-z0-9]{20,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}\b', '[REDACTED_GITHUB_TOKEN]')
    return $out
}

function Hide-Id {
    [CmdletBinding()] param([AllowNull()][string]$Id)
    if ([string]::IsNullOrWhiteSpace($Id)) { return '' }
    if ($Id.Length -le 8) { return '********' }
    return $Id.Substring(0, 8) + '…'
}

# --- safe external tools ---------------------------------------------------

function Invoke-Tool {
    <# Runs one allowlisted executable with a fixed argument array. Arguments are passed as an array; strings are never evaluated as code. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$File, [string[]]$Arguments = @(), [string]$WorkingDirectory)
    if ($File -notin $script:ToolAllowlist) { Stop-Requirements -Exit SECURITY_BLOCKED -Message "TOOL_NOT_ALLOWLISTED: $File" }
    $command = Get-Command -Name $File -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { return [pscustomobject]@{ Found = $false; ExitCode = -1; Output = '' } }
    $previous = Get-Location
    try {
        if ($WorkingDirectory) { Set-Location -LiteralPath $WorkingDirectory }
        $lines = & $command.Source @Arguments 2>&1 | ForEach-Object { $_.ToString() }
        return [pscustomobject]@{ Found = $true; ExitCode = $LASTEXITCODE; Output = ($lines -join "`n") }
    }
    finally { Set-Location -LiteralPath $previous }
}

function Invoke-GraphGet {
    <# Read-only Microsoft Graph v1.0 GET through the existing az login. Anything else is rejected before any call. #>
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Url)
    if ($Url -notmatch '^https://graph\.microsoft\.com/v1\.0/[A-Za-z0-9_/.:$=,()%?&'' @-]+$') { Stop-Requirements -Exit SECURITY_BLOCKED -Message 'GRAPH_URL_NOT_ALLOWED' }
    $result = Invoke-Tool -File az -Arguments @('rest', '--method', 'GET', '--url', $Url, '-o', 'json')
    if (-not $result.Found) { return [pscustomobject]@{ Ok = $false; Reason = 'PREREQUISITE_MISSING'; Data = $null } }
    if ($result.ExitCode -ne 0) {
        $reason = if ($result.Output -match 'Unauthorized|401|AADSTS|login') { 'AUTHENTICATION_REQUIRED' } elseif ($result.Output -match 'Forbidden|403|Authorization_RequestDenied') { 'PERMISSION_DENIED' } else { 'REQUEST_FAILED' }
        return [pscustomobject]@{ Ok = $false; Reason = $reason; Data = $null }
    }
    return [pscustomobject]@{ Ok = $true; Reason = ''; Data = ($result.Output | ConvertFrom-Json) }
}

function Invoke-MgGet {
    <# Read-only GET through an EXISTING Microsoft Graph PowerShell session. It never connects, never prompts and rejects anything but v1.0 GET URLs. #>
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Url)
    if ($Url -notmatch '^https://graph\.microsoft\.com/v1\.0/places(/[A-Za-z0-9_.-]{1,128}|/microsoft\.graph\.[A-Za-z]{3,20})(\?[A-Za-z0-9=$,._&%-]{0,200})?$') { Stop-Requirements -Exit SECURITY_BLOCKED -Message 'GRAPH_URL_NOT_ALLOWED' }
    if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue) -or -not (Get-MgContext -ErrorAction SilentlyContinue)) { return [pscustomobject]@{ Ok = $false; Reason = 'AUTHENTICATION_REQUIRED'; Data = $null } }
    try { return [pscustomobject]@{ Ok = $true; Reason = ''; Data = (Invoke-MgGraphRequest -Method GET -Uri $Url -ErrorAction Stop) } }
    catch { $r = if ($_.Exception.Message -match '403|Forbidden') { 'PERMISSION_DENIED' } elseif ($_.Exception.Message -match '404|NotFound') { 'NOT_FOUND' } elseif ($_.Exception.Message -match '401|Unauthorized') { 'AUTHENTICATION_REQUIRED' } else { 'REQUEST_FAILED' }; return [pscustomobject]@{ Ok = $false; Reason = $r; Data = $null } }
}

function Read-EnvValue {
    <# Reads only named keys from a KEY=VALUE file. The file is never executed or dumped. #>
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][ValidatePattern('^[A-Z][A-Z0-9_]{1,64}$')][string]$Key)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $line = Get-Content -LiteralPath $Path | Where-Object { $_ -match "^\s*$([regex]::Escape($Key))\s*=" } | Select-Object -Last 1
    if (-not $line) { return $null }
    return (($line -split '=', 2)[1]).Trim().Trim('"').Trim("'")
}

# --- action authorization --------------------------------------------------

function Assert-ActionAuthorized {
    <#
    .SYNOPSIS
      Central gate. READ_ONLY and LOCAL_MUTATION need nothing further. Every class above that needs the exact
      environment, change reference, target, operation, approval evidence, confirmed effective permissions and a matching tenant.
      There is deliberately no -Force or -AutoApprove: nothing can bypass this gate.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('READ_ONLY','LOCAL_MUTATION','TENANT_MUTATION','PRIVILEGED_MUTATION','DESTRUCTIVE')][string]$Class,
        [Parameter(Mandatory)][string]$ActionName,
        [string]$Environment, [string]$ChangeReference, [string]$TargetIdentity, [string]$Operation,
        [string]$ApprovalEvidencePath, [switch]$EffectivePermissionsConfirmed,
        [string]$ExpectedTenantId, [string]$ActualTenantId
    )
    if ($Class -in 'READ_ONLY', 'LOCAL_MUTATION') { return }
    if ([string]::IsNullOrWhiteSpace($ExpectedTenantId) -or [string]::IsNullOrWhiteSpace($ActualTenantId)) { Stop-Requirements -Exit AUTHENTICATION_REQUIRED -Message 'TENANT_NOT_VERIFIED' }
    if ($ExpectedTenantId -ne $ActualTenantId) { Stop-Requirements -Exit SECURITY_BLOCKED -Message 'TENANT_MISMATCH' }
    if ($Environment -ne 'development') { Stop-Requirements -Exit SECURITY_BLOCKED -Message 'ENVIRONMENT_NOT_AUTHORIZED' }
    foreach ($pair in @(@('ChangeReference', $ChangeReference, '^[A-Za-z0-9][A-Za-z0-9._/-]{3,63}$'), @('TargetIdentity', $TargetIdentity, '^[A-Za-z0-9][A-Za-z0-9@._:/-]{2,127}$'), @('Operation', $Operation, '^[A-Za-z][A-Za-z0-9]{2,63}$'))) {
        if ([string]::IsNullOrWhiteSpace($pair[1]) -or $pair[1] -notmatch $pair[2]) { Stop-Requirements -Exit APPROVAL_REQUIRED -Message "MISSING_OR_INVALID_$($pair[0].ToUpperInvariant())" }
    }
    if ($Operation -ne $ActionName) { Stop-Requirements -Exit APPROVAL_REQUIRED -Message 'OPERATION_NAME_MISMATCH' }
    if ([string]::IsNullOrWhiteSpace($ApprovalEvidencePath) -or -not (Test-Path -LiteralPath $ApprovalEvidencePath -PathType Leaf)) { Stop-Requirements -Exit APPROVAL_REQUIRED -Message 'APPROVAL_EVIDENCE_MISSING' }
    try { $evidence = Get-Content -LiteralPath $ApprovalEvidencePath -Raw | ConvertFrom-Json } catch { Stop-Requirements -Exit VALIDATION_FAILED -Message 'APPROVAL_EVIDENCE_UNREADABLE' }
    $names = @($evidence.PSObject.Properties.Name)
    foreach ($required in 'status', 'changeReference', 'environment', 'operation', 'targetIdentity', 'approvedBy', 'expiresAt') { if ($names -notcontains $required) { Stop-Requirements -Exit VALIDATION_FAILED -Message 'APPROVAL_EVIDENCE_INCOMPLETE' } }
    if ($evidence.status -cne 'APPROVED') { Stop-Requirements -Exit APPROVAL_REQUIRED -Message 'APPROVAL_NOT_APPROVED' }
    if ($evidence.changeReference -cne $ChangeReference -or $evidence.environment -cne $Environment -or $evidence.operation -cne $Operation -or $evidence.targetIdentity -cne $TargetIdentity) { Stop-Requirements -Exit APPROVAL_REQUIRED -Message 'APPROVAL_DOES_NOT_MATCH_REQUEST' }
    $expires = [datetimeoffset]::MinValue
    # ConvertFrom-Json turns ISO timestamps into DateTime; parse strings culture-invariantly so the check does not depend on the machine locale.
    $parsed = if ($evidence.expiresAt -is [datetime]) { $expires = [datetimeoffset]$evidence.expiresAt; $true } else { [datetimeoffset]::TryParse([string]$evidence.expiresAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$expires) }
    if (-not $parsed -or $expires -lt [datetimeoffset]::UtcNow) { Stop-Requirements -Exit APPROVAL_REQUIRED -Message 'APPROVAL_EXPIRED' }
    if (-not $EffectivePermissionsConfirmed) { Stop-Requirements -Exit APPROVAL_REQUIRED -Message 'EFFECTIVE_PERMISSIONS_NOT_CONFIRMED' }
}

# --- results and reports -------------------------------------------------

function New-CheckResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Check,
          [Parameter(Mandatory)][ValidateSet('OK','WARN','FAIL','BLOCKED','NOT_TESTED','INFO')][string]$Status,
          [string]$Detail = '', [string]$Gate = '')
    [pscustomobject]@{ check = $Check; status = $Status; detail = (Protect-Text $Detail); gate = (Protect-Text $Gate) }
}

function Write-RequirementsReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Results, [Parameter(Mandatory)][string]$Directory, [string]$Command = 'Status', [string]$Environment = 'development')
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $clean = @($Results | ForEach-Object { [pscustomobject]@{ check = $_.check; status = $_.status; detail = (Protect-Text $_.detail); gate = (Protect-Text $_.gate) } })
    $report = [ordered]@{
        generatedAt = [datetimeoffset]::UtcNow.ToString('o')
        command = $Command
        environment = $Environment
        liveReadVerified = $false
        liveWriteVerified = $false
        note = 'Static and local results are not live evidence. liveReadVerified and liveWriteVerified stay false until an authorized tenant test has succeeded.'
        summary = [ordered]@{ ok = @($clean | Where-Object status -eq 'OK').Count; warn = @($clean | Where-Object status -eq 'WARN').Count; fail = @($clean | Where-Object status -eq 'FAIL').Count; blocked = @($clean | Where-Object status -eq 'BLOCKED').Count; notTested = @($clean | Where-Object status -eq 'NOT_TESTED').Count }
        results = $clean
    }
    $jsonPath = Join-Path $Directory 'requirements-status.json'
    $mdPath = Join-Path $Directory 'requirements-status.md'
    ($report | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM
    $md = [System.Text.StringBuilder]::new()
    [void]$md.AppendLine('# PlaceHub requirements status')
    [void]$md.AppendLine('')
    [void]$md.AppendLine("Generated: $($report.generatedAt) · command: $Command · environment: $Environment")
    [void]$md.AppendLine('')
    [void]$md.AppendLine('> Live read and live write are **not verified** by this report. Static and local results are not tenant evidence.')
    [void]$md.AppendLine('')
    [void]$md.AppendLine('| Check | Status | Detail | Remaining gate |')
    [void]$md.AppendLine('|---|---|---|---|')
    foreach ($r in $clean) { [void]$md.AppendLine("| $($r.check) | $($r.status) | $(($r.detail -replace '\|','/' -replace '\r?\n',' ')) | $(($r.gate -replace '\|','/' -replace '\r?\n',' ')) |") }
    Protect-Text $md.ToString() | Set-Content -LiteralPath $mdPath -Encoding utf8NoBOM
    [pscustomobject]@{ Json = $jsonPath; Markdown = $mdPath }
}

Export-ModuleMember -Function Get-RequirementsExitCodes, Get-RequirementsActionClasses, Stop-Requirements, Protect-Text, Hide-Id, Invoke-Tool, Invoke-GraphGet, Invoke-MgGet, Read-EnvValue, Assert-ActionAuthorized, New-CheckResult, Write-RequirementsReport
