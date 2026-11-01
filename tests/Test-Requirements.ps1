$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$entry = Join-Path $root 'scripts/Invoke-PlaceHub-Requirements.ps1'
$modulePath = Join-Path $root 'scripts/PlaceHub.Requirements.psm1'
Import-Module $modulePath -Force
$codes = Get-RequirementsExitCodes
$temp = Join-Path ([IO.Path]::GetTempPath()) ("placehub-req-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null

function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Get-ExitName { param([scriptblock]$Body) try { & $Body; 'NONE' } catch { if ($_.Exception.PSObject.Properties['ExitName']) { $_.Exception.ExitName } else { 'OTHER:' + $_.Exception.Message } } }

try {
    # --- every script parses (existing scripts keep working as scripts) ---
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -Include '*.ps1', '*.psm1' -Recurse) {
        $errors = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
        Assert-True ($errors.Count -eq 0) "SCRIPT_PARSE_ERROR $($file.Name)"
    }

    # --- help, command surface and exit-code documentation ---
    $help = (& pwsh -NoProfile -File $entry Help) -join "`n"; Assert-True ($LASTEXITCODE -eq $codes.SUCCESS) 'HELP_EXIT'
    foreach ($command in 'Help','Status','CheckPrerequisites','CheckAzureLogin','CheckTenant','CheckGitHubAuth','CheckRepository','CheckADRs','CheckEntraApplications','CheckAppRoles','CheckGraphPermissions','CheckConsentStatus','CheckPlacesInventory','CheckExchangeResources','CheckCertificates','CheckKeyVaultBoundary','CheckTerraform','CheckDocker','Restore','Build','Test','TestSecurity','TestArchitecture','TestTerraformPolicy','ValidateCompose','DockerBuild','DockerUp','DockerDown','TerraformPlan','PrepareActivation','PrepareConsent','PrepareRoleAssignment','PrepareBuildingBootstrap','VerifyLiveRead','VerifyLiveWrite','CheckConsent','CheckWorkerIdentity','CheckParkingMailboxes','DiagnosePlacesHierarchy','ValidateTerraform','PrepareTerraformPlan','PrepareRoleAssignments','PrepareParkingProvisioning','TestUi') {
        Assert-True ($help -match "(?m)^$command\s") "COMMAND_MISSING_FROM_HELP $command"
    }
    foreach ($class in 'READ_ONLY','LOCAL_MUTATION','TENANT_MUTATION','PRIVILEGED_MUTATION','DESTRUCTIVE') { Assert-True ($help -match $class) "CLASS_MISSING $class" }
    foreach ($name in 'SUCCESS=0','PREREQUISITE_MISSING=10','AUTHENTICATION_REQUIRED=20','APPROVAL_REQUIRED=30','VALIDATION_FAILED=40','SECURITY_BLOCKED=50','EXECUTION_FAILED=60') { Assert-True ($help.Contains($name)) "EXIT_CODE_UNDOCUMENTED $name" }

    # --- unknown commands cannot run; no Force/AutoApprove exists; non-development environment is blocked ---
    $null = & pwsh -NoProfile -File $entry 'Format-Disk' 2>&1; Assert-True ($LASTEXITCODE -eq $codes.VALIDATION_FAILED) 'UNKNOWN_COMMAND_RAN'
    $null = & pwsh -NoProfile -File $entry 'Help;calc' 2>&1; Assert-True ($LASTEXITCODE -eq $codes.VALIDATION_FAILED) 'INJECTED_COMMAND_RAN'
    $null = & pwsh -NoProfile -File $entry CheckKeyVaultBoundary -Environment production -ReportDirectory $temp 2>&1; Assert-True ($LASTEXITCODE -eq $codes.SECURITY_BLOCKED) 'PRODUCTION_NOT_BLOCKED'
    $null = & pwsh -NoProfile -File $entry CheckKeyVaultBoundary -Force 2>&1; Assert-True ($LASTEXITCODE -ne 0) 'FORCE_PARAMETER_ACCEPTED'
    $null = & pwsh -NoProfile -File $entry CheckKeyVaultBoundary -AutoApprove 2>&1; Assert-True ($LASTEXITCODE -ne 0) 'AUTOAPPROVE_PARAMETER_ACCEPTED'

    # --- source safety: no dynamic execution, no mutation verbs, no apply, no token extraction ---
    $source = (Get-Content -LiteralPath $entry -Raw) + (Get-Content -LiteralPath $modulePath -Raw)
    foreach ($forbidden in 'Invoke-Expression','iex ','operation=apply','get-access-token','--method'', ''POST','--method'', ''PATCH','--method'', ''PUT','--method'', ''DELETE','credential reset','admin-consent','Connect-ExchangeOnline','Connect-MgGraph','Remove-Item','terraform'', ''apply','-auto-approve') {
        Assert-True (-not $source.Contains($forbidden)) "FORBIDDEN_CONSTRUCT $forbidden"
    }
    Assert-True (([regex]::Matches($source, "'operation=plan'")).Count -eq 1) 'TERRAFORM_PLAN_OPERATION_NOT_FIXED'
    $param = [regex]::Match((Get-Content -LiteralPath $entry -Raw), '(?s)param\((.*?)\)\s*\r?\n\s*Set-StrictMode').Groups[1].Value
    Assert-True ($param -notmatch '(?i)\bForce\b|AutoApprove|SkipApproval|Bypass') 'BYPASS_PARAMETER_PRESENT'

    # --- tool and Graph allowlists ---
    Assert-True ((Get-ExitName { Invoke-Tool -File 'curl' -Arguments @('https://example.invalid') }) -eq 'SECURITY_BLOCKED') 'TOOL_ALLOWLIST_MISSING'
    Assert-True ((Get-ExitName { Invoke-Tool -File 'bash' -Arguments @('-c', 'id') }) -eq 'SECURITY_BLOCKED') 'SHELL_ALLOWED'
    foreach ($url in 'https://example.com/v1.0/me', 'http://graph.microsoft.com/v1.0/me', 'https://graph.microsoft.com/beta/places', 'https://graph.microsoft.com/v1.0/me; id') {
        Assert-True ((Get-ExitName { Invoke-GraphGet $url }) -eq 'SECURITY_BLOCKED') "GRAPH_URL_ACCEPTED $url"
    }

    # --- privileged gate: every missing element blocks; only a complete, matching, unexpired record passes ---
    $tenant = '11111111-1111-1111-1111-111111111111'
    $good = [ordered]@{ status = 'APPROVED'; changeReference = 'CHG-1001'; environment = 'development'; operation = 'PlacesCreate'; targetIdentity = 'building-1'; approvedBy = 'owner'; expiresAt = ([datetimeoffset]::UtcNow.AddHours(2).ToString('o')) }
    $evidence = Join-Path $temp 'approval.json'
    function Write-Evidence { param($Data) ($Data | ConvertTo-Json) | Set-Content -LiteralPath $evidence -Encoding utf8NoBOM }
    function Invoke-Gate {
        param([string]$Class = 'PRIVILEGED_MUTATION', [hashtable]$Override = @{})
        $args = @{ Class = $Class; ActionName = 'PlacesCreate'; Environment = 'development'; ChangeReference = 'CHG-1001'; TargetIdentity = 'building-1'; Operation = 'PlacesCreate'; ApprovalEvidencePath = $evidence; EffectivePermissionsConfirmed = $true; ExpectedTenantId = $tenant; ActualTenantId = $tenant }
        foreach ($k in $Override.Keys) { $args[$k] = $Override[$k] }
        Assert-ActionAuthorized @args
    }
    Write-Evidence $good
    foreach ($class in 'TENANT_MUTATION', 'PRIVILEGED_MUTATION', 'DESTRUCTIVE') { Assert-True ((Get-ExitName { Invoke-Gate -Class $class }) -eq 'NONE') "COMPLETE_APPROVAL_REJECTED $class" }
    Assert-True ((Get-ExitName { Invoke-Gate -Class 'READ_ONLY' -Override @{ ApprovalEvidencePath = ''; ActualTenantId = '' } }) -eq 'NONE') 'READ_ONLY_REQUIRES_APPROVAL'
    $cases = [ordered]@{
        'missing approval file' = @{ ApprovalEvidencePath = (Join-Path $temp 'none.json') }; 'no evidence path' = @{ ApprovalEvidencePath = '' }
        'no change reference' = @{ ChangeReference = '' }; 'no target' = @{ TargetIdentity = '' }; 'no operation' = @{ Operation = '' }
        'operation differs from action' = @{ Operation = 'OtherOperation' }; 'wrong environment' = @{ Environment = 'production' }
        'effective permissions unconfirmed' = @{ EffectivePermissionsConfirmed = $false }; 'wrong tenant' = @{ ActualTenantId = '22222222-2222-2222-2222-222222222222' }
        'unknown tenant' = @{ ActualTenantId = '' }; 'invalid reference characters' = @{ ChangeReference = 'CHG;rm -rf' }
    }
    foreach ($name in $cases.Keys) { Assert-True ((Get-ExitName { Invoke-Gate -Override $cases[$name] }) -in 'APPROVAL_REQUIRED', 'SECURITY_BLOCKED', 'AUTHENTICATION_REQUIRED') "GATE_DID_NOT_BLOCK: $name" }
    $mutations = [ordered]@{ 'status not approved' = @{ status = 'PENDING' }; 'other change reference' = @{ changeReference = 'CHG-9999' }; 'other target' = @{ targetIdentity = 'building-2' }; 'other operation' = @{ operation = 'Other' }; 'other environment' = @{ environment = 'production' }; 'expired' = @{ expiresAt = ([datetimeoffset]::UtcNow.AddHours(-1).ToString('o')) } }
    foreach ($name in $mutations.Keys) { $copy = [ordered]@{} + $good; foreach ($k in $mutations[$name].Keys) { $copy[$k] = $mutations[$name][$k] }; Write-Evidence $copy; Assert-True ((Get-ExitName { Invoke-Gate }) -in 'APPROVAL_REQUIRED', 'SECURITY_BLOCKED') "EVIDENCE_NOT_ENFORCED: $name" }
    $incomplete = [ordered]@{} + $good; $incomplete.Remove('approvedBy'); Write-Evidence $incomplete; Assert-True ((Get-ExitName { Invoke-Gate }) -eq 'VALIDATION_FAILED') 'INCOMPLETE_EVIDENCE_ACCEPTED'
    'not json' | Set-Content -LiteralPath $evidence; Assert-True ((Get-ExitName { Invoke-Gate }) -eq 'VALIDATION_FAILED') 'UNREADABLE_EVIDENCE_ACCEPTED'
    Assert-True ((Get-ExitName { Invoke-Gate -Class 'DESTRUCTIVE' }) -ne 'NONE') 'DESTRUCTIVE_BYPASSED_AUTHORIZATION'

    # --- secrets never reach reports ---
    $jwt = 'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.c2lnbmF0dXJlc2lnbmF0dXJl'
    $canaries = @($jwt, 'client_secret=SuperSecretCanary123', 'password: "hunter2canary"', 'Bearer abcdefghijklmnopqrstuvwxyz0123', 'ghp_abcdefghijklmnopqrstuvwxyz0123456789', "-----BEGIN PRIVATE KEY-----`nMIIEvQIBADANBgkq`n-----END PRIVATE KEY-----")
    foreach ($canary in $canaries) { $clean = Protect-Text "value $canary end"; Assert-True ($clean -match 'REDACTED') "NOT_REDACTED $canary"; foreach ($fragment in 'SuperSecretCanary123','hunter2canary','MIIEvQIBADANBgkq','c2lnbmF0dXJl','abcdefghijklmnopqrstuvwxyz0123') { Assert-True (-not $clean.Contains($fragment)) "SECRET_FRAGMENT_LEAKED $fragment" } }
    $results = @($canaries | ForEach-Object { [pscustomobject]@{ check = 'synthetic'; status = 'OK'; detail = $_; gate = $_ } })
    $paths = Write-RequirementsReport -Results $results -Directory (Join-Path $temp 'report') -Command 'Test'
    $reportText = (Get-Content -LiteralPath $paths.Json -Raw) + (Get-Content -LiteralPath $paths.Markdown -Raw)
    foreach ($fragment in 'SuperSecretCanary123','hunter2canary','MIIEvQIBADANBgkq','c2lnbmF0dXJl','abcdefghijklmnopqrstuvwxyz0123','ghp_abcdefghijklmnopqrstuvwxyz') { Assert-True (-not $reportText.Contains($fragment)) "REPORT_LEAKED $fragment" }
    $json = Get-Content -LiteralPath $paths.Json -Raw | ConvertFrom-Json
    Assert-True ($json.liveReadVerified -eq $false -and $json.liveWriteVerified -eq $false) 'REPORT_CLAIMS_LIVE_SUCCESS'

    # --- real local commands: no tenant mutation, honest live status ---
    $run = Join-Path $temp 'run'
    $null = & pwsh -NoProfile -File $entry CheckKeyVaultBoundary -ReportDirectory $run; Assert-True ($LASTEXITCODE -eq $codes.SUCCESS) 'KEYVAULT_BOUNDARY_CHECK_FAILED'
    $null = & pwsh -NoProfile -File $entry PrepareBuildingBootstrap -ReportDirectory $run; Assert-True ($LASTEXITCODE -eq $codes.SUCCESS) 'BOOTSTRAP_CHECK_FAILED'
    $bootstrap = (Get-Content -LiteralPath (Join-Path $run 'requirements-status.json') -Raw | ConvertFrom-Json).results | Where-Object check -eq 'prepare.bootstrapManifest'
    Assert-True ($bootstrap.status -eq 'BLOCKED') 'UNAPPROVED_BOOTSTRAP_MANIFEST_NOT_BLOCKED'
    $null = & pwsh -NoProfile -File $entry VerifyLiveWrite -ReportDirectory $run; Assert-True ($LASTEXITCODE -eq $codes.SUCCESS) 'LIVE_WRITE_STATUS_FAILED'
    $liveWrite = (Get-Content -LiteralPath (Join-Path $run 'requirements-status.json') -Raw | ConvertFrom-Json).results | Where-Object check -eq 'live.write'
    Assert-True ($liveWrite.status -eq 'NOT_TESTED') 'LIVE_WRITE_CLAIMED_WITHOUT_EVIDENCE'
    foreach ($artifact in 'requirements-status.json', 'requirements-status.md') { Assert-True (Test-Path -LiteralPath (Join-Path $run $artifact)) "REPORT_MISSING $artifact" }

    # --- Graph PowerShell reads are GET-only, places-only and never connect ---
    foreach ($url in 'https://graph.microsoft.com/v1.0/users', 'https://graph.microsoft.com/beta/places', 'https://graph.microsoft.com/v1.0/places/../users', 'https://graph.microsoft.com/v1.0/places/x?$select=a;b') {
        Assert-True ((Get-ExitName { Invoke-MgGet $url }) -eq 'SECURITY_BLOCKED') "MG_URL_ACCEPTED $url"
    }
    $null = & pwsh -NoProfile -File $entry DiagnosePlacesHierarchy -ReportDirectory $run -PlaceId 'a;calc' 2>&1; Assert-True ($LASTEXITCODE -ne 0) 'PLACEID_INJECTION_ACCEPTED'
    $null = & pwsh -NoProfile -File $entry DiagnosePlacesHierarchy -ReportDirectory $run 2>&1; Assert-True ($LASTEXITCODE -eq $codes.SUCCESS) 'DIAGNOSE_WITHOUT_SESSION_SHOULD_REPORT_BLOCKED_NOT_FAIL'
    $diag = ((Get-Content -LiteralPath (Join-Path $run 'requirements-status.json') -Raw | ConvertFrom-Json).results | Where-Object check -eq 'diagnose.outcome')
    Assert-True ($null -ne $diag -and $diag.status -in 'BLOCKED', 'INFO') 'DIAGNOSE_OUTCOME_MISSING'
    $null = & pwsh -NoProfile -File $entry PrepareParkingProvisioning -ReportDirectory $run; Assert-True ($LASTEXITCODE -eq $codes.SUCCESS -and (Test-Path -LiteralPath (Join-Path $run 'parking-provisioning-proposal.md'))) 'PARKING_PROPOSAL_NOT_WRITTEN'
    $null = & pwsh -NoProfile -File $entry CheckParkingMailboxes -ReportDirectory $run; Assert-True ($LASTEXITCODE -eq $codes.SUCCESS) 'PARKING_CHECK_FAILED'
    $pm = ((Get-Content -LiteralPath (Join-Path $run 'requirements-status.json') -Raw | ConvertFrom-Json).results | Where-Object check -eq 'parking.exchangeInventory')
    Assert-True ($pm.status -eq 'NOT_TESTED') 'EXCHANGE_INVENTORY_CLAIMED_WITHOUT_SESSION'

    # --- existing test scripts are still present and untouched in purpose ---
    foreach ($existing in 'Test-Static.ps1','Test-DockerCompose.ps1','Test-Microsoft365Readiness.ps1','Test-TerraformPlanClassifier.ps1') { Assert-True (Test-Path -LiteralPath (Join-Path $root "tests/$existing")) "EXISTING_TEST_MISSING $existing" }
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
'REQUIREMENTS_SCRIPT_TESTS_OK'
