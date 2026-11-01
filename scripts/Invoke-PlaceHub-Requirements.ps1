#requires -Version 7.0
<#
.SYNOPSIS
  Central entry point for PlaceHub operational requirements and local console tasks.
.DESCRIPTION
  Composes the existing scripts and tests; it does not replace them. Every command is classified
  (READ_ONLY, LOCAL_MUTATION, TENANT_MUTATION, PRIVILEGED_MUTATION, DESTRUCTIVE). This script implements no tenant mutation:
  consent, role assignment, certificate registration, Terraform apply and Places writes are only prepared, never executed.
  There is no -Force or -AutoApprove parameter. Run `Help` for the command list.
.EXAMPLE
  pwsh scripts/Invoke-PlaceHub-Requirements.ps1 Status
.EXAMPLE
  pwsh scripts/Invoke-PlaceHub-Requirements.ps1 Test
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Command = 'Help',
    [string]$Environment = 'development',
    [ValidateSet('Live', 'Synthetic')][string]$DockerProfile = 'Live',
    [string]$ReportDirectory,
    [string]$ChangeReference,
    [string]$TargetIdentity,
    [string]$Operation,
    [string]$ApprovalEvidencePath,
    [switch]$EffectivePermissionsConfirmed,
    [switch]$Watch,
    [ValidatePattern('^[A-Za-z0-9._-]{1,128}$')][string[]]$PlaceId = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot 'PlaceHub.Requirements.psm1') -Force
if (-not $ReportDirectory) { $ReportDirectory = Join-Path $root 'artifacts' }

$FrontendName = 'placehub-frontend-development'
$ProvisioningName = 'placehub-m365-provisioning-development'
$GraphAppId = '00000003-0000-0000-c000-000000000000'
$ExpectedRoles = @{ 'PlaceHub.OfficeManager' = '166b3fc4-fb93-401b-b856-bffa0d682447'; 'PlaceHub.LocationManager' = '228e1fa0-cca2-4ac4-bc44-987ee444ba4c'; 'PlaceHub.SystemAdministrator' = '9a3f940c-08c4-4bd7-8cfa-106eaab349a5' }
$envFile = Join-Path $root '.env'

function Res { param([string]$Check, [string]$Status, [string]$Detail = '', [string]$Gate = '') New-CheckResult -Check $Check -Status $Status -Detail $Detail -Gate $Gate }
function Get-App { param([string]$Name) $r = Invoke-GraphGet "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq '$Name'"; if ($r.Ok -and @($r.Data.value).Count -gt 0) { [pscustomobject]@{ Ok = $true; App = $r.Data.value[0]; Reason = '' } } else { [pscustomobject]@{ Ok = $false; App = $null; Reason = $(if ($r.Ok) { 'NOT_FOUND' } else { $r.Reason }) } } }
function Get-Sp { param([string]$AppId) $r = Invoke-GraphGet "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$AppId'"; if ($r.Ok -and @($r.Data.value).Count -gt 0) { $r.Data.value[0] } else { $null } }
function Test-Version { param([string]$Actual, [string]$Minimum) try { [version]($Actual -replace '[^0-9.].*$', '') -ge [version]$Minimum } catch { $false } }
function Invoke-Script { param([string]$Path, [string[]]$Arguments = @()) $o = Invoke-Tool -File pwsh -Arguments (@('-NoProfile', '-File', $Path) + $Arguments) -WorkingDirectory $root; $o }
function Get-Current-Tenant { $a = Invoke-Tool -File az -Arguments @('account', 'show', '--query', 'tenantId', '-o', 'tsv'); if ($a.Found -and $a.ExitCode -eq 0) { $a.Output.Trim() } else { $null } }

# ---- read-only checks --------------------------------------------------------

function Check-Prerequisites {
    $needs = @(
        @{ n = 'pwsh'; a = @('-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()'); min = '7.4' },
        @{ n = 'dotnet'; a = @('--version'); min = '10.0' },
        @{ n = 'docker'; a = @('--version'); min = '24.0' },
        @{ n = 'terraform'; a = @('version'); min = '1.16' },
        @{ n = 'az'; a = @('--version'); min = '2.60' },
        @{ n = 'gh'; a = @('--version'); min = '2.40' },
        @{ n = 'git'; a = @('--version'); min = '2.40' })
    foreach ($t in $needs) {
        $o = Invoke-Tool -File $t.n -Arguments $t.a
        if (-not $o.Found) { Res "tool.$($t.n)" 'FAIL' 'Not installed' "Install $($t.n) >= $($t.min)"; continue }
        $v = ([regex]::Match($o.Output, '\d+\.\d+(\.\d+)?')).Value
        if (Test-Version $v $t.min) { Res "tool.$($t.n)" 'OK' "version $v (required >= $($t.min))" } else { Res "tool.$($t.n)" 'FAIL' "version $v (required >= $($t.min))" "Upgrade $($t.n)" }
    }
}

function Check-AzureLogin {
    $o = Invoke-Tool -File az -Arguments @('account', 'show', '--query', '{user:user.name,type:user.type,state:state}', '-o', 'json')
    if (-not $o.Found) { return Res 'azure.login' 'FAIL' 'Azure CLI missing' 'Install Azure CLI' }
    if ($o.ExitCode -ne 0) { return Res 'azure.login' 'BLOCKED' 'No active az login' 'Run az login (interactive)' }
    $a = $o.Output | ConvertFrom-Json
    Res 'azure.login' 'OK' "signed in as $($a.type) account, subscription state $($a.state)"
}

function Check-Tenant {
    $expected = Read-EnvValue -Path $envFile -Key 'AZURE_TENANT_ID'
    $actual = Get-Current-Tenant
    if (-not $expected) { return Res 'tenant.binding' 'FAIL' '.env has no AZURE_TENANT_ID' 'Set AZURE_TENANT_ID in .env' }
    if (-not $actual) { return Res 'tenant.binding' 'BLOCKED' 'Tenant could not be read' 'Run az login' }
    if ($expected -ne $actual) { return Res 'tenant.binding' 'FAIL' "active tenant $(Hide-Id $actual) differs from expected $(Hide-Id $expected)" 'Select the correct tenant; execution is blocked' }
    Res 'tenant.binding' 'OK' "active tenant $(Hide-Id $actual) matches .env"
    $all = Invoke-Tool -File az -Arguments @('account', 'list', '--query', 'length(@)', '-o', 'tsv')
    if ($all.Found -and $all.ExitCode -eq 0) { Res 'tenant.subscriptions' 'INFO' "$($all.Output.Trim()) subscriptions visible; default subscription is never changed by this script" }
}

function Check-GitHubAuth {
    $o = Invoke-Tool -File gh -Arguments @('auth', 'status')
    if (-not $o.Found) { return Res 'github.auth' 'FAIL' 'gh missing' 'Install GitHub CLI' }
    if ($o.ExitCode -eq 0) { Res 'github.auth' 'OK' 'authenticated (token not shown)' } else { Res 'github.auth' 'BLOCKED' 'not authenticated' 'Run gh auth login' }
}

function Check-Repository {
    $branch = (Invoke-Tool -File git -Arguments @('rev-parse', '--abbrev-ref', 'HEAD') -WorkingDirectory $root).Output.Trim()
    $head = (Invoke-Tool -File git -Arguments @('rev-parse', '--short', 'HEAD') -WorkingDirectory $root).Output.Trim()
    $dirty = @((Invoke-Tool -File git -Arguments @('status', '--porcelain') -WorkingDirectory $root).Output -split "`n" | Where-Object { $_ }).Count
    Res 'repo.revision' 'INFO' "branch $branch at $head, $dirty uncommitted path(s)"
    $tracked = (Invoke-Tool -File git -Arguments @('ls-files') -WorkingDirectory $root).Output -split "`n"
    $bad = @($tracked | Where-Object { $_ -match '\.(pfx|key|pem|p12)$' -or $_ -eq '.env' })
    if ($bad.Count -eq 0) { Res 'repo.noSecretFilesTracked' 'OK' 'no .env, key or certificate files are tracked' } else { Res 'repo.noSecretFilesTracked' 'FAIL' "$($bad.Count) forbidden file(s) tracked" 'Remove from Git and rotate' }
    $pr = Invoke-Tool -File gh -Arguments @('pr', 'list', '--state', 'open', '--json', 'number', '-q', 'length')
    if ($pr.Found -and $pr.ExitCode -eq 0) { Res 'repo.openPullRequests' 'INFO' "$($pr.Output.Trim()) open pull request(s)" }
}

function Check-ADRs {
    $dir = Join-Path $root 'Docs/Adr'
    $adrs = Get-ChildItem -LiteralPath $dir -Filter 'ADR-*.md'
    Res 'adr.count' 'INFO' "$($adrs.Count) ADR files"
    foreach ($n in '004', '005', '015', '017') {
        $f = $adrs | Where-Object Name -like "ADR-$n-*"; if (-not $f) { Res "adr.$n" 'FAIL' 'missing'; continue }
        $text = Get-Content -LiteralPath $f.FullName -Raw
        $proposed = $text -match 'Status: PROPOSED'; $target = $text -match 'Status: ACCEPTED as target architecture'
        Res "adr.$n" $(if ($proposed) { 'WARN' } else { 'OK' }) $(if ($proposed) { 'contains a PROPOSED amendment, not Accepted' } elseif ($target) { 'amendment accepted as target architecture; operative rights are not approved' } else { 'no pending amendment' }) $(if ($proposed) { 'Project Owner acceptance of the amendment text' } elseif ($target) { 'Operative permissions, consent, RBAC, apply and worker activation stay gated' } else { '' })
    }
    $indexOk = (Get-Content -LiteralPath (Join-Path $dir 'README.md') -Raw) -match '\[004\]'
    Res 'adr.index' $(if ($indexOk) { 'OK' } else { 'FAIL' }) 'ADR index present'
}

function Check-EntraApplications {
    foreach ($name in $FrontendName, $ProvisioningName) {
        $a = Get-App $name
        if (-not $a.Ok) { Res "entra.$name" 'BLOCKED' $a.Reason 'Run az login with directory read access'; continue }
        $keys = @($a.App.keyCredentials).Count; $pw = @($a.App.passwordCredentials).Count
        Res "entra.$name" 'OK' "app $(Hide-Id $a.App.appId), audience $($a.App.signInAudience), $keys certificate(s), $pw secret(s)"
        if ($pw -gt 0) { Res "entra.$name.secrets" 'FAIL' 'client secrets are not allowed' 'Remove the secret' }
    }
    $f = Get-App $FrontendName
    if ($f.Ok) {
        $uris = @($f.App.web.redirectUris)
        $want = @('https://localhost:3242/signin-oidc', 'https://localhost:8443/signin-oidc')
        Res 'entra.redirectUris' $(if (-not (Compare-Object $uris $want)) { 'OK' } else { 'FAIL' }) "$($uris.Count) redirect URI(s)"
    }
}

function Check-AppRoles {
    $f = Get-App $FrontendName; if (-not $f.Ok) { return Res 'entra.appRoles' 'BLOCKED' $f.Reason 'az login' }
    foreach ($k in $ExpectedRoles.Keys) {
        $role = @($f.App.appRoles) | Where-Object value -eq $k
        if ($role -and $role.id -eq $ExpectedRoles[$k] -and (@($role.allowedMemberTypes) -contains 'User')) { Res "entra.role.$k" 'OK' 'stable ID matches' } else { Res "entra.role.$k" 'FAIL' 'missing or ID differs' }
    }
}

function Check-GraphPermissions {
    $policy = Get-Content -LiteralPath (Join-Path $root 'infrastructure/terraform/policy/development.json') -Raw | ConvertFrom-Json
    $expect = @($policy.applications.'azuread_application.placehub_web'.required_resource_access.resource_access | ForEach-Object { "$($_.type):$($_.id)" }) | Sort-Object
    $f = Get-App $FrontendName
    if ($f.Ok) {
        $actual = @($f.App.requiredResourceAccess | Where-Object resourceAppId -eq $GraphAppId | ForEach-Object { $_.resourceAccess } | ForEach-Object { "$($_.type):$($_.id)" }) | Sort-Object
        $diff = Compare-Object -ReferenceObject @($expect) -DifferenceObject @($actual)
        Res 'graph.frontendDeclared' $(if (-not $diff) { 'OK' } else { 'FAIL' }) "declared $(@($actual).Count) delegated read scope(s); policy expects $(@($expect).Count)"
    } else { Res 'graph.frontendDeclared' 'BLOCKED' $f.Reason 'az login' }
    $p = Get-App $ProvisioningName
    if ($p.Ok) { $n = @($p.App.requiredResourceAccess).Count; Res 'graph.provisioningDeclared' $(if ($n -eq 0) { 'OK' } else { 'WARN' }) "$n resource declaration(s); Place.ReadWrite.All is only proposed" 'Terraform policy amendment + apply (separate approval)' }
    $graph = Invoke-GraphGet "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$GraphAppId'&`$select=oauth2PermissionScopes,appRoles"
    if ($graph.Ok) {
        $scopes = $graph.Data.value[0].oauth2PermissionScopes; $roles = $graph.Data.value[0].appRoles
        $ids = @{ 'Place.Read.All' = 'cb8f45a0-5c2e-4ea1-b803-84b870a7d7ec'; 'Calendars.ReadBasic' = '662d75ba-a364-42ad-adee-f5f880ea4878' }
        foreach ($k in $ids.Keys) { $s = $scopes | Where-Object value -eq $k; Res "graph.permissionId.$k" $(if ($s -and $s.id -eq $ids[$k]) { 'OK' } else { 'FAIL' }) "consent type $($s.type)" }
        $rw = $roles | Where-Object value -eq 'Place.ReadWrite.All'; if ($rw) { Res 'graph.permissionId.Place.ReadWrite.All(app)' 'INFO' "application role ID $(Hide-Id $rw.id) (proposed only, not granted)" }
    }
}

function Check-ConsentStatus {
    $f = Get-App $FrontendName; if (-not $f.Ok) { return Res 'consent.frontend' 'BLOCKED' $f.Reason 'az login' }
    $sp = Get-Sp $f.App.appId; if (-not $sp) { return Res 'consent.frontend' 'FAIL' 'service principal missing' }
    $g = Invoke-GraphGet "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$($sp.id)'"
    $a = Invoke-GraphGet "https://graph.microsoft.com/v1.0/servicePrincipals/$($sp.id)/appRoleAssignedTo"
    if ($g.Ok) {
        $grants = @($g.Data.value); $scopes = @($grants | ForEach-Object { ($_.scope -split ' ') | Where-Object { $_ } }) | Sort-Object -Unique
        $tenantWide = @($grants | Where-Object consentType -eq 'AllPrincipals').Count -gt 0
        $ok = ($scopes -contains 'Place.Read.All') -and ($scopes -contains 'Calendars.ReadBasic') -and $tenantWide
        Res 'consent.delegatedGrants' $(if ($ok) { 'OK' } else { 'BLOCKED' }) ("scopes granted: " + $(if ($scopes) { $scopes -join ', ' } else { 'none' }) + "; tenant-wide consent: $tenantWide") $(if (-not $ok) { 'Administrator consent for Place.Read.All (not authorized by this script)' } else { '' })
    }
    if ($a.Ok) {
        $names = @{ '166b3fc4-fb93-401b-b856-bffa0d682447' = 'OfficeManager'; '228e1fa0-cca2-4ac4-bc44-987ee444ba4c' = 'LocationManager'; '9a3f940c-08c4-4bd7-8cfa-106eaab349a5' = 'SystemAdministrator'; '00000000-0000-0000-0000-000000000000' = 'DefaultAccess(no PlaceHub role)' }
        $rows = @($a.Data.value | ForEach-Object { "$($_.principalType) $(Hide-Id $_.principalId) -> $(if ($names.ContainsKey($_.appRoleId)) { $names[$_.appRoleId] } else { 'unknown role' })" })
        $withRole = @($a.Data.value | Where-Object { $names[$_.appRoleId] -and $_.appRoleId -ne '00000000-0000-0000-0000-000000000000' }).Count
        Res 'consent.roleAssignments' $(if ($withRole -gt 0) { 'OK' } else { 'BLOCKED' }) ("$($rows.Count) assignment(s): " + ($rows -join '; ')) $(if ($withRole -eq 0) { 'Approved principal assignment (not executed)' } else { '' })
    }
    $p = Get-Sp ((Get-App $ProvisioningName).App.appId)
    if ($p) { $pa = Invoke-GraphGet "https://graph.microsoft.com/v1.0/servicePrincipals/$($p.id)/appRoleAssignments"; if ($pa.Ok) { $n = @($pa.Data.value).Count; Res 'consent.provisioningGrants' $(if ($n -eq 0) { 'OK' } else { 'WARN' }) "$n application permission grant(s) on the provisioning identity" } }
}

function Check-PlacesInventory {
    $types = 'building', 'floor', 'section', 'workspace', 'desk', 'room', 'roomList'
    $blocked = $false
    foreach ($t in $types) {
        $r = Invoke-GraphGet "https://graph.microsoft.com/v1.0/places/microsoft.graph.$t"
        if ($r.Ok) { Res "places.$t" 'OK' "$(@($r.Data.value).Count) item(s) visible to this identity" }
        else { $blocked = $true; Res "places.$t" 'BLOCKED' $r.Reason 'The Azure CLI token has no Places read permission; use DiagnosePlacesHierarchy from a Graph PowerShell session that has the Place.Read.All scope' }
    }
    if ($blocked) { Res 'places.inventoryComplete' 'BLOCKED' 'inventory is incomplete; an empty or failed read is not proof of absence' 'Complete inventory before the first write' }
}

function Check-ExchangeResources {
    $m = Get-Module -ListAvailable -Name ExchangeOnlineManagement | Select-Object -First 1
    Res 'exchange.resourceMailboxes' 'NOT_TESTED' $(if ($m) { 'module present; this script never opens an Exchange session' } else { 'ExchangeOnlineManagement not installed' }) 'Run Get-Mailbox -RecipientTypeDetails RoomMailbox,WorkspaceMailbox interactively as an administrator'
}

function Check-Certificates {
    $dir = Read-EnvValue -Path $envFile -Key 'PLACEHUB_TLS_DIRECTORY'
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return Res 'cert.directory' 'BLOCKED' 'PLACEHUB_TLS_DIRECTORY missing or unreadable' 'Run scripts/Initialize-LocalTls.ps1' }
    $names = @(Get-ChildItem -LiteralPath $dir -File | Select-Object -ExpandProperty Name)
    Res 'cert.tls' $(if (($names -contains 'tls.crt') -and ($names -contains 'tls.key')) { 'OK' } else { 'BLOCKED' }) 'local HTTPS certificate files present (contents never read)'
    $hasPfx = $names -contains 'client-auth.pfx'; $hasCer = $names -contains 'client-auth.cer'
    Res 'cert.webClientCredential' $(if ($hasPfx -and $hasCer) { 'OK' } else { 'BLOCKED' }) "private file present: $hasPfx, public file present: $hasCer" $(if (-not ($hasPfx -and $hasCer)) { 'Generation requires recorded authorization (scripts/Initialize-LocalEntraCertificate.ps1)' } else { '' })
    if ($hasCer) {
        try { $c = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new((Join-Path $dir 'client-auth.cer')); $days = [int]($c.NotAfter - [datetime]::UtcNow).TotalDays; Res 'cert.webClientExpiry' $(if ($days -gt 30) { 'OK' } elseif ($days -gt 0) { 'WARN' } else { 'FAIL' }) "public certificate expires in $days day(s); thumbprint $(Hide-Id $c.Thumbprint)" }
        catch { Res 'cert.webClientExpiry' 'FAIL' 'public certificate unreadable' }
    }
    $f = Get-App $FrontendName
    if ($f.Ok) {
        $keys = @($f.App.keyCredentials); $k = $keys.Count; $match = $false
        if ($hasCer) { try { $local = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new((Join-Path $dir 'client-auth.cer')).Thumbprint; $match = @($keys | Where-Object { $_.customKeyIdentifier -and $_.customKeyIdentifier -ieq $local }).Count -gt 0 } catch { $match = $false } }
        Res 'cert.registeredInEntra' $(if ($k -gt 0) { 'OK' } else { 'BLOCKED' }) "$k public certificate(s) registered on the web application" $(if ($k -eq 0) { 'Credential registration approval (ADR-016 option B)' } else { '' })
        if ($k -gt 0 -and $hasCer) { Res 'cert.registeredMatchesLocal' $(if ($match) { 'OK' } else { 'FAIL' }) $(if ($match) { 'registered thumbprint equals the local public certificate' } else { 'no registered certificate matches the local public certificate' }) }
    }
}

function Check-KeyVaultBoundary {
    $compose = Get-Content -LiteralPath (Join-Path $root 'compose.yaml') -Raw
    $web = ($compose -split 'placehub-worker:')[0]
    Res 'boundary.webNoKeyVault' $(if ($web -notmatch '(?i)keyvault|vault\.azure|AZURE_CLIENT') { 'OK' } else { 'FAIL' }) 'web service has no Key Vault or Azure credential configuration'
    Res 'boundary.noDockerSocket' $(if ($compose -notmatch 'docker\.sock') { 'OK' } else { 'FAIL' }) 'Docker socket is not mounted'
    $workerPorts = ($compose -split 'placehub-worker:')[1] -match '(?m)^\s+ports:'
    Res 'boundary.workerNoPublishedPort' $(if (-not $workerPorts) { 'OK' } else { 'FAIL' }) 'worker publishes no port'
    Res 'boundary.workerDisabledByDefault' $(if ($compose -match 'Worker__Enabled:\s*"false"') { 'OK' } else { 'FAIL' }) 'worker is disabled by default'
    $tf = (Get-ChildItem -LiteralPath (Join-Path $root 'infrastructure/terraform') -Filter '*.tf' | Get-Content -Raw) -join "`n"
    Res 'boundary.noActiveKeyVaultInTerraform' $(if ($tf -notmatch 'azurerm_key_vault') { 'OK' } else { 'WARN' }) 'no active Key Vault resource is declared (worker vault is a gated proposal)' 'Key Vault apply authorization'
}

function Check-Terraform {
    $dir = Join-Path $root 'infrastructure/terraform'
    $fmt = Invoke-Tool -File terraform -Arguments @('fmt', '-check', '-recursive') -WorkingDirectory $dir
    if (-not $fmt.Found) { return Res 'terraform.fmt' 'FAIL' 'terraform missing' 'Install Terraform' }
    Res 'terraform.fmt' $(if ($fmt.ExitCode -eq 0) { 'OK' } else { 'FAIL' }) 'terraform fmt -check'
    if (Test-Path (Join-Path $dir '.terraform')) { $v = Invoke-Tool -File terraform -Arguments @('validate', '-no-color') -WorkingDirectory $dir; Res 'terraform.validate' $(if ($v.ExitCode -eq 0) { 'OK' } else { 'FAIL' }) 'terraform validate' }
    else { Res 'terraform.validate' 'NOT_TESTED' 'not initialized locally' 'terraform init -backend=false (local cache only)' }
    Res 'terraform.apply' 'NOT_TESTED' 'this script never applies' 'Apply only through the ADR-016 workflow with explicit authorization'
}

function Check-Docker {
    $v = Invoke-Tool -File docker -Arguments @('version', '--format', '{{.Server.Version}}')
    if (-not $v.Found -or $v.ExitCode -ne 0) { return Res 'docker.engine' 'BLOCKED' 'Docker engine not reachable' 'Start Docker Desktop' }
    Res 'docker.engine' 'OK' "server $($v.Output.Trim())"
    $c = Invoke-Tool -File docker -Arguments @('compose', '-f', 'compose.yaml', 'config', '-q') -WorkingDirectory $root
    Res 'docker.composeConfig' $(if ($c.ExitCode -eq 0) { 'OK' } else { 'FAIL' }) $(if ($c.ExitCode -eq 0) { 'compose.yaml resolves' } else { 'compose.yaml does not resolve (variables missing?)' })
    $ps = Invoke-Tool -File docker -Arguments @('compose', 'ps', '--format', '{{.Service}}:{{.State}}') -WorkingDirectory $root
    $h = Invoke-Tool -File docker -Arguments @('ps', '--filter', 'name=placehub', '--format', '{{.Names}}={{.Status}}') -WorkingDirectory $root
    foreach ($line in @($h.Output -split "`n" | Where-Object { $_ })) {
        $name = ($line -split '=', 2)[0]; $state = ($line -split '=', 2)[1]
        $status = if ($state -match 'unhealthy') { 'FAIL' } elseif ($state -match 'healthy') { 'OK' } else { 'WARN' }
        Res "docker.health.$name" $status ($state -replace '\d+ (seconds?|minutes?|hours?)', 'n units')
    }
    Res 'docker.containers' 'INFO' $(if ($ps.Output.Trim()) { $ps.Output.Trim() -replace "`n", ', ' } else { 'no containers running' })
}

# ---- local mutation / test commands ---------------------------------------

function Run-Step { param([string]$Name, [scriptblock]$Body) $o = & $Body; $tail = (($o.Output -split "`n" | Select-Object -Last 3) -join ' | '); Res $Name $(if ($o.ExitCode -eq 0) { 'OK' } else { 'FAIL' }) $tail }
function Do-Restore { Run-Step 'dotnet.restore' { Invoke-Tool -File dotnet -Arguments @('restore', 'PlaceHub.slnx', '--nologo') -WorkingDirectory $root } }
function Do-Build { Run-Step 'dotnet.build' { Invoke-Tool -File dotnet -Arguments @('build', 'PlaceHub.slnx', '-c', 'Release', '--nologo') -WorkingDirectory $root } }
function Do-Test { Run-Step 'dotnet.test' { Invoke-Tool -File dotnet -Arguments @('test', 'PlaceHub.slnx', '-c', 'Release', '--nologo') -WorkingDirectory $root } }
function Do-PsTests { param([string]$Prefix, [string[]]$Names) foreach ($n in $Names) { $o = Invoke-Script (Join-Path $root "tests/$n"); Res "$Prefix.$([IO.Path]::GetFileNameWithoutExtension($n))" $(if ($o.ExitCode -eq 0) { 'OK' } else { 'FAIL' }) (($o.Output -split "`n" | Select-Object -Last 1)) } }
function Do-TestSecurity {
    Do-PsTests 'security' @('Test-Static.ps1', 'Test-Microsoft365Authentication.ps1', 'Test-GitHubEnvironment.ps1', 'Test-Requirements.ps1')
    $files = (Invoke-Tool -File git -Arguments @('ls-files') -WorkingDirectory $root).Output -split "`n" | Where-Object { $_ -and $_ -notmatch '\.(png|jpg|ico|dll|pdf)$' -and $_ -ne 'tests/Test-Requirements.ps1' }
    $hits = foreach ($f in $files) { $p = Join-Path $root $f; if (Test-Path -LiteralPath $p -PathType Leaf) { $t = Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue; if ($t -and $t -match '-----BEGIN [A-Z ]*PRIVATE KEY-----|\bgh[pousr]_[A-Za-z0-9]{30,}\b|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}') { $f } } }
    Res 'security.secretScan' $(if (@($hits).Count -eq 0) { 'OK' } else { 'FAIL' }) "$(@($hits).Count) tracked file(s) contain secret-like material"
}
function Do-TestArchitecture { Do-PsTests 'architecture' @('Test-Static.ps1', 'Test-UIStatic.ps1', 'Test-Microsoft365Readiness.ps1', 'Test-ProvisioningMock.ps1'); $o = Invoke-Tool -File dotnet -Arguments @('test', 'PlaceHub.slnx', '-c', 'Release', '--nologo', '--filter', 'FullyQualifiedName~FourEyes|FullyQualifiedName~PlacesProvisioning|FullyQualifiedName~AdministrationWorkflow') -WorkingDirectory $root; Res 'architecture.workflowAndFourEyes' $(if ($o.ExitCode -eq 0) { 'OK' } else { 'FAIL' }) (($o.Output -split "`n" | Select-Object -Last 1)) }
function Do-TestTerraformPolicy { Do-PsTests 'terraformPolicy' @('Test-TerraformPlanClassifier.ps1', 'Test-Microsoft365PermissionProposal.ps1') }
function Do-ValidateCompose { Do-PsTests 'compose' @('Test-DockerCompose.ps1') }
function Do-DockerBuild { $a = Get-ComposeArguments; Run-Step "docker.build.$DockerProfile" { Invoke-Tool -File docker -Arguments ($a + @('build')) -WorkingDirectory $root } }
function Get-ComposeArguments { if ($DockerProfile -eq 'Synthetic') { @('compose', '-p', 'placehub-synthetic', '-f', 'compose.yaml', '-f', 'compose.synthetic-test.yaml') } else { @('compose', '-f', 'compose.yaml') } }
function Do-DockerUp { $a = Get-ComposeArguments; Run-Step "docker.up.$DockerProfile" { Invoke-Tool -File docker -Arguments ($a + @('up', '-d')) -WorkingDirectory $root } }
function Do-DockerDown { $a = Get-ComposeArguments; Run-Step "docker.down.$DockerProfile" { Invoke-Tool -File docker -Arguments ($a + @('down')) -WorkingDirectory $root } }

function Do-TestUi {
    # Renders every page in Microsoft Edge (Playwright) against the synthetic profile and checks the unauthenticated live redirect.
    # Authenticated live pages need a real Entra sign-in and are NOT covered; they must be reviewed by a person.
    $py = Invoke-Tool -File python -Arguments @('-c', 'import playwright') -WorkingDirectory $root
    if (-not $py.Found -or $py.ExitCode -ne 0) { return Res 'ui.rendered' 'NOT_TESTED' 'python with Playwright is not available' 'pip install playwright (Microsoft Edge is used; no browser download)' }
    $health = Invoke-Tool -File docker -Arguments @('ps', '--filter', 'name=placehub-synthetic-placehub-web', '--format', '{{.Status}}') -WorkingDirectory $root
    if ($health.Output -notmatch 'Up') { return Res 'ui.rendered' 'BLOCKED' 'the synthetic profile is not running' 'Run DockerBuild and DockerUp with -DockerProfile Synthetic, and keep the live profile up for the redirect check' }
    $out = Join-Path $ReportDirectory 'ui-evidence'
    $r = Invoke-Tool -File python -Arguments @((Join-Path $root 'tests/ui/ui_review.py'), '--out', $out) -WorkingDirectory (Join-Path $root 'tests/ui')
    $last = ($r.Output -split "`n" | Where-Object { $_ } | Select-Object -Last 1)
    Res 'ui.rendered' $(if ($r.ExitCode -eq 0) { 'OK' } else { 'FAIL' }) "$last (screenshots and ui-review.json in $out; synthetic profile only)" 'Authenticated live pages require a manual or credentialed review'
}

function Do-TerraformPlan {
    if ($Environment -ne 'development') { Stop-Requirements -Exit SECURITY_BLOCKED -Message 'ENVIRONMENT_NOT_AUTHORIZED' }
    # Fixed operation=plan: triggers a CI plan through the ADR-016 workflow; apply is never requested.
    $o = Invoke-Tool -File gh -Arguments @('workflow', 'run', 'terraform.yml', '--ref', 'main', '-f', 'target_environment=development', '-f', 'operation=plan') -WorkingDirectory $root
    if (-not $o.Found) { Stop-Requirements -Exit PREREQUISITE_MISSING -Message 'gh missing' }
    if ($o.ExitCode -ne 0) { Stop-Requirements -Exit EXECUTION_FAILED -Message 'plan dispatch failed' }
    Res 'terraform.planDispatched' 'OK' ('plan workflow dispatched on main; no apply requested; ' + ($o.Output -split "`n" | Select-Object -Last 1)) 'Review the classification; apply needs separate authorization'
}

# ---- preparation (writes only under artifacts/) ---------------------------

function Prepare-Activation { Run-Status; Res 'activation.package' 'INFO' 'see requirements-status.md for remaining gates' }
function Prepare-Consent {
    $f = Get-App $FrontendName
    $text = @"
# Administrator consent request (NOT EXECUTED)

- Application: $FrontendName ($(if ($f.Ok) { Hide-Id $f.App.appId } else { 'id unavailable' }))
- Permission: Microsoft Graph delegated Place.Read.All (cb8f45a0-5c2e-4ea1-b803-84b870a7d7ec) - administrator consent required
- Permission: Microsoft Graph delegated Calendars.ReadBasic (662d75ba-a364-42ad-adee-f5f880ea4878) - tenant consent policy not verified
- Required role: Cloud Application Administrator, Application Administrator or Global Administrator
- Scope: this application only; no write permission, no application permission
- Evidence after consent: oauth2PermissionGrants record for the service principal (run CheckConsentStatus)
"@
    New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
    $p = Join-Path $ReportDirectory 'consent-request.md'; Protect-Text $text | Set-Content -LiteralPath $p -Encoding utf8NoBOM
    Res 'prepare.consent' 'OK' "written to $p" 'Administrator approval and action'
}
function Prepare-RoleAssignment {
    $m = Get-Content -LiteralPath (Join-Path $root 'infrastructure/terraform/proposals/development-app-role-assignments.json') -Raw | ConvertFrom-Json
    $n = @($m.proposed_assignments).Count
    New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
    $p = Join-Path $ReportDirectory 'role-assignment-proposal.json'; Protect-Text ($m.proposed_assignments | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $p -Encoding utf8NoBOM
    Res 'prepare.roleAssignment' 'OK' "$n proposed assignment(s) copied to $p; effective_assignment_authorized=$($m.effective_assignment_authorized)" 'Approved principal and building; assignment is not executed here'
}
function Prepare-BuildingBootstrap {
    $path = Join-Path $root 'infrastructure/places/development-bootstrap-manifest.json'
    if (-not (Test-Path -LiteralPath $path)) { return Res 'prepare.bootstrap' 'FAIL' 'manifest file missing' }
    $m = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $approved = $m.status -ceq 'APPROVED_BY_PROJECT_OWNER'
    Res 'prepare.bootstrapManifest' $(if ($approved) { 'OK' } else { 'BLOCKED' }) "status $($m.status), $(@($m.entries).Count) entr(ies), environment $($m.environment)" $(if (-not $approved) { 'Project Owner supplies exact building definition; no names are invented' } else { '' })
}
function Verify-LiveRead {
    $missing = @()
    $f = Get-App $FrontendName
    if ($f.Ok) {
        $sp = Get-Sp $f.App.appId
        $g = Invoke-GraphGet "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$($sp.id)'"
        if (-not ($g.Ok -and @($g.Data.value).Count -gt 0)) { $missing += 'admin consent for Place.Read.All' }
        $a = Invoke-GraphGet "https://graph.microsoft.com/v1.0/servicePrincipals/$($sp.id)/appRoleAssignedTo"
        if (-not ($a.Ok -and @($a.Data.value).Count -gt 0)) { $missing += 'application role assignment' }
        if (@($f.App.keyCredentials).Count -eq 0) { $missing += 'registered web certificate' }
    } else { $missing += 'Entra application readable' }
    $oid = Read-EnvValue -Path $envFile -Key 'PLACEHUB_USER_OBJECT_ID'; $loc = Read-EnvValue -Path $envFile -Key 'PLACEHUB_LOCATION_PLACE_ID'
    if (-not $oid -or $oid -eq 'UNASSIGNED' -or -not $loc -or $loc -eq 'UNASSIGNED') { $missing += 'server-side location assignment (an approved building placeId)' }
    if (@($missing).Count -gt 0) { return Res 'live.read' 'BLOCKED' ('prerequisites missing: ' + ($missing -join '; ')) 'Complete the listed gates; no live success is claimed' }
    Res 'live.read' 'NOT_TESTED' 'prerequisites present; an interactive sign-in, scp claim check, Places read and getSchedule must be performed and recorded' 'Perform the interactive live test'
}
function Verify-LiveWrite { Res 'live.write' 'NOT_TESTED' 'no authorized Places write has been executed; read-after-write evidence is required' 'ADR acceptance, worker identity, permissions, Exchange RBAC and Terraform apply approvals' }


function Check-WorkerIdentity {
    $p = Get-App $ProvisioningName
    if ($p.Ok) {
        $secrets = @($p.App.passwordCredentials).Count; $certs = @($p.App.keyCredentials).Count; $perms = @($p.App.requiredResourceAccess).Count
        Res 'worker.identitySeparate' 'OK' "provisioning app $(Hide-Id $p.App.appId) is distinct from the web app $(Hide-Id (Get-App $FrontendName).App.appId)"
        Res 'worker.noSecret' $(if ($secrets -eq 0) { 'OK' } else { 'FAIL' }) "$secrets client secret(s)"
        Res 'worker.credential' $(if ($certs -gt 0) { 'OK' } else { 'BLOCKED' }) "$certs registered certificate(s)" $(if ($certs -eq 0) { 'Worker certificate enrollment and registration (separate approval)' } else { '' })
        Res 'worker.declaredPermissions' $(if ($perms -eq 0) { 'OK' } else { 'WARN' }) "$perms resource declaration(s); Place.ReadWrite.All is proposed only" 'Terraform policy amendment, plan, apply, consent (separate approvals)'
        $sp = Get-Sp $p.App.appId
        if ($sp) { $g = Invoke-GraphGet "https://graph.microsoft.com/v1.0/servicePrincipals/$($sp.id)/appRoleAssignments"; if ($g.Ok) { $n = @($g.Data.value).Count; Res 'worker.effectiveGrants' $(if ($n -eq 0) { 'OK' } else { 'WARN' }) "$n application permission grant(s) effective" } }
    } else { Res 'worker.identity' 'BLOCKED' $p.Reason 'az login' }
    $compose = Get-Content -LiteralPath (Join-Path $root 'compose.yaml') -Raw
    Res 'worker.disabled' $(if ($compose -match 'Worker__Enabled:\s*"false"') { 'OK' } else { 'FAIL' }) 'worker disabled by default in Compose'
    Res 'worker.rbac' 'NOT_TESTED' 'Exchange RBAC for Applications (TenantPlacesManagement, MailRecipient) is not assigned and its assignability is unproven' 'Security review; never granted by this script'
}

function Check-ParkingMailboxes {
    Res 'parking.exchangeInventory' 'NOT_TESTED' 'this script never opens an Exchange session' 'Run interactively as an administrator: Get-EXOMailbox -RecipientTypeDetails EquipmentMailbox,RoomMailbox -ResultSize 50'
    Res 'parking.mailboxTypeDecision' 'BLOCKED' 'ADR-006 has not selected Equipment versus Room; creation is refused while undecided' 'Project Owner decision'
    Res 'parking.provisioningGates' 'BLOCKED' 'worker, MailboxCreationApproved, approved domain and name prefix, runner: all closed' 'See PrepareParkingProvisioning'
}

function Diagnose-PlacesHierarchy {
    $types = 'building', 'floor', 'section', 'room', 'roomList', 'workspace', 'desk'
    $listed = @{}; $blocked = $null
    foreach ($t in $types) {
        $r = Invoke-MgGet "https://graph.microsoft.com/v1.0/places/microsoft.graph.$t"
        if ($r.Ok) { $listed[$t] = @($r.Data.value).Count; Res "diagnose.list.$t" 'OK' "$($listed[$t]) item(s) in the typed list" }
        else { $blocked = $r.Reason; Res "diagnose.list.$t" 'BLOCKED' $r.Reason }
    }
    if ($blocked) { return Res 'diagnose.outcome' 'BLOCKED' "UNKNOWN: $blocked" 'Open a Microsoft Graph PowerShell session with the Place.Read.All scope in this terminal, then rerun (single pass, no polling)' }
    $found = 0
    foreach ($id in $PlaceId) {
        $r = Invoke-MgGet "https://graph.microsoft.com/v1.0/places/$id"
        if ($r.Ok) { $found++; Res "diagnose.byId.$(Hide-Id $id)" 'OK' "readable by id as $(([string]$r.Data.'@odata.type') -replace '^#microsoft\.graph\.','')" }
        else { Res "diagnose.byId.$(Hide-Id $id)" 'WARN' $r.Reason }
    }
    $total = ($listed.Values | Measure-Object -Sum).Sum
    $outcome = if ($found -gt 0 -and $listed['building'] -eq 0) { 'INCONSISTENT_DIRECTORY_STATE' } elseif ($found -gt 0) { 'RESOURCE_FOUND' } elseif ($total -eq 0) { 'VERIFIED_EMPTY' } else { 'RESOURCE_FOUND' }
    Res 'diagnose.outcome' 'INFO' "$outcome (counts only; a propagation delay is not asserted without evidence from an earlier run)" $(if ($outcome -eq 'INCONSISTENT_DIRECTORY_STATE') { 'Cause unproven; do not create duplicates' } else { '' })
}

function Prepare-ParkingProvisioning {
    New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
    $text = @"
# Parking provisioning activation package (NOT EXECUTED)

Typed operations: DiscoverResourceMailbox, ImportExistingParkingResource, CreateParkingResource, UpdateParkingResource, ConfigureBookingPolicy, DisableParkingResource, VerifyProvisioningState, ReconcileParkingResource.
Fixed cmdlets: Get-EXOMailbox, Get-CalendarProcessing, New-Mailbox (-Equipment or -Room), Set-Mailbox (DisplayName), Set-CalendarProcessing (policy template parameters). No Remove-*, no deletion.

Open decisions and approvals (all required before any live use):
1. ADR-006: mailbox type (Equipment or Room), exact naming rules (prefix, SMTP domain), disable semantics, booking policy templates.
2. Security acceptance of the organization-wide New-Mailbox residual risk, or a documented safer alternative.
3. Worker identity, certificate and Key Vault access (worker only); web has none.
4. Exchange RBAC for Applications: assignability and scope unproven.
5. A real, pinned ExchangeOnlineManagement runner after the clean-room proof.
6. Terraform: policy amendment, exact plan, apply authorization.
"@
    $p = Join-Path $ReportDirectory 'parking-provisioning-proposal.md'; Protect-Text $text | Set-Content -LiteralPath $p -Encoding utf8NoBOM
    Res 'prepare.parkingProvisioning' 'OK' "written to $p" 'All listed approvals'
}

function Prepare-TerraformPlan { Res 'prepare.terraformPlan' 'INFO' 'run the TerraformPlan command (dispatches the ADR-016 workflow with operation=plan only); review the sanitized classification before any apply request' 'Apply needs separate authorization' }

# ---- orchestration ----------------------------------------------------

$script:Collected = [System.Collections.Generic.List[object]]::new()
function Add-Results { param($Items) foreach ($i in @($Items)) { if ($null -ne $i) { $script:Collected.Add($i) } } }
function Run-Status {
    foreach ($fn in 'Check-Prerequisites', 'Check-AzureLogin', 'Check-Tenant', 'Check-GitHubAuth', 'Check-Repository', 'Check-ADRs', 'Check-EntraApplications', 'Check-AppRoles', 'Check-GraphPermissions', 'Check-ConsentStatus', 'Check-PlacesInventory', 'Check-ExchangeResources', 'Check-Certificates', 'Check-KeyVaultBoundary', 'Check-Terraform', 'Check-Docker') {
        try { Add-Results (& $fn) } catch { if ($_.Exception.PSObject.Properties['ExitName']) { Add-Results (Res $fn 'FAIL' $_.Exception.Message) } else { Add-Results (Res $fn 'FAIL' 'check failed unexpectedly') } }
    }
    Add-Results (Verify-LiveRead); Add-Results (Verify-LiveWrite)
}

# command -> class, summary, handler
$Commands = [ordered]@{
    Help = @{ Class = 'READ_ONLY'; Info = 'List commands, classes and exit codes' }
    Status = @{ Class = 'READ_ONLY'; Info = 'Run every read-only check and write artifacts/requirements-status.json and .md'; Run = { Run-Status } }
    CheckPrerequisites = @{ Class = 'READ_ONLY'; Info = 'Tool availability and versions'; Run = { Add-Results (Check-Prerequisites) } }
    CheckAzureLogin = @{ Class = 'READ_ONLY'; Info = 'Azure CLI session'; Run = { Add-Results (Check-AzureLogin) } }
    CheckTenant = @{ Class = 'READ_ONLY'; Info = 'Active tenant equals .env tenant'; Run = { Add-Results (Check-Tenant) } }
    CheckGitHubAuth = @{ Class = 'READ_ONLY'; Info = 'GitHub CLI authentication'; Run = { Add-Results (Check-GitHubAuth) } }
    CheckRepository = @{ Class = 'READ_ONLY'; Info = 'Branch, working tree, tracked secret files, open PRs'; Run = { Add-Results (Check-Repository) } }
    CheckADRs = @{ Class = 'READ_ONLY'; Info = 'ADR index and pending amendments'; Run = { Add-Results (Check-ADRs) } }
    CheckEntraApplications = @{ Class = 'READ_ONLY'; Info = 'Entra applications, credentials, redirects'; Run = { Add-Results (Check-EntraApplications) } }
    CheckAppRoles = @{ Class = 'READ_ONLY'; Info = 'Stable app-role IDs'; Run = { Add-Results (Check-AppRoles) } }
    CheckGraphPermissions = @{ Class = 'READ_ONLY'; Info = 'Declared permissions versus policy; IDs versus Graph'; Run = { Add-Results (Check-GraphPermissions) } }
    CheckConsentStatus = @{ Class = 'READ_ONLY'; Info = 'Effective consent grants and role assignments'; Run = { Add-Results (Check-ConsentStatus) } }
    CheckPlacesInventory = @{ Class = 'READ_ONLY'; Info = 'Places families visible to this identity'; Run = { Add-Results (Check-PlacesInventory) } }
    CheckExchangeResources = @{ Class = 'READ_ONLY'; Info = 'Exchange resource mailboxes (never opens a session)'; Run = { Add-Results (Check-ExchangeResources) } }
    CheckCertificates = @{ Class = 'READ_ONLY'; Info = 'Local certificate files and public registration'; Run = { Add-Results (Check-Certificates) } }
    CheckKeyVaultBoundary = @{ Class = 'READ_ONLY'; Info = 'Web/worker/Key Vault boundary in Compose and Terraform'; Run = { Add-Results (Check-KeyVaultBoundary) } }
    CheckTerraform = @{ Class = 'READ_ONLY'; Info = 'terraform fmt and validate'; Run = { Add-Results (Check-Terraform) } }
    CheckDocker = @{ Class = 'READ_ONLY'; Info = 'Docker engine, compose config, containers'; Run = { Add-Results (Check-Docker) } }
    Restore = @{ Class = 'LOCAL_MUTATION'; Info = 'dotnet restore'; Run = { Add-Results (Do-Restore) } }
    Build = @{ Class = 'LOCAL_MUTATION'; Info = 'dotnet build -c Release'; Run = { Add-Results (Do-Build) } }
    Test = @{ Class = 'LOCAL_MUTATION'; Info = 'dotnet test -c Release'; Run = { Add-Results (Do-Test) } }
    TestSecurity = @{ Class = 'READ_ONLY'; Info = 'Static security tests and tracked-file secret scan'; Run = { Add-Results (Do-TestSecurity) } }
    TestArchitecture = @{ Class = 'READ_ONLY'; Info = 'Architecture, readiness, workflow and four-eyes tests'; Run = { Add-Results (Do-TestArchitecture) } }
    TestTerraformPolicy = @{ Class = 'READ_ONLY'; Info = 'Plan classifier and permission proposal tests'; Run = { Add-Results (Do-TestTerraformPolicy) } }
    TestUi = @{ Class = 'LOCAL_MUTATION'; Info = 'Render all pages in Edge against the synthetic profile and write screenshots (artifacts/ui-evidence)'; Run = { Add-Results (Do-TestUi) } }
    ValidateCompose = @{ Class = 'READ_ONLY'; Info = 'Compose static checks'; Run = { Add-Results (Do-ValidateCompose) } }
    DockerBuild = @{ Class = 'LOCAL_MUTATION'; Info = 'docker compose build'; Run = { Add-Results (Do-DockerBuild) } }
    DockerUp = @{ Class = 'LOCAL_MUTATION'; Info = 'docker compose up -d (-DockerProfile Live|Synthetic)'; Run = { Add-Results (Do-DockerUp) } }
    DockerDown = @{ Class = 'LOCAL_MUTATION'; Info = 'docker compose down'; Run = { Add-Results (Do-DockerDown) } }
    CheckConsent = @{ Class = 'READ_ONLY'; Info = 'Alias of CheckConsentStatus'; Run = { Add-Results (Check-ConsentStatus) } }
    CheckWorkerIdentity = @{ Class = 'READ_ONLY'; Info = 'Worker identity separation, credentials, effective grants'; Run = { Add-Results (Check-WorkerIdentity) } }
    CheckParkingMailboxes = @{ Class = 'READ_ONLY'; Info = 'Parking mailbox gates (never opens an Exchange session)'; Run = { Add-Results (Check-ParkingMailboxes) } }
    DiagnosePlacesHierarchy = @{ Class = 'READ_ONLY'; Info = 'Single-pass Places diagnosis through an existing Microsoft Graph PowerShell session (-PlaceId optional)'; Run = { Add-Results (Diagnose-PlacesHierarchy) } }
    ValidateTerraform = @{ Class = 'READ_ONLY'; Info = 'Alias of CheckTerraform'; Run = { Add-Results (Check-Terraform) } }
    PrepareTerraformPlan = @{ Class = 'READ_ONLY'; Info = 'Explain the plan procedure; TerraformPlan dispatches it'; Run = { Add-Results (Prepare-TerraformPlan) } }
    PrepareRoleAssignments = @{ Class = 'LOCAL_MUTATION'; Info = 'Alias of PrepareRoleAssignment'; Run = { Add-Results (Prepare-RoleAssignment) } }
    PrepareParkingProvisioning = @{ Class = 'LOCAL_MUTATION'; Info = 'Write artifacts/parking-provisioning-proposal.md (nothing is executed)'; Run = { Add-Results (Prepare-ParkingProvisioning) } }
    TerraformPlan = @{ Class = 'READ_ONLY'; Info = 'Dispatch the ADR-016 plan workflow (operation=plan only; never apply)'; Run = { Add-Results (Do-TerraformPlan) } }
    PrepareActivation = @{ Class = 'READ_ONLY'; Info = 'Status report with remaining gates'; Run = { Prepare-Activation } }
    PrepareConsent = @{ Class = 'LOCAL_MUTATION'; Info = 'Write artifacts/consent-request.md (consent is not granted)'; Run = { Add-Results (Prepare-Consent) } }
    PrepareRoleAssignment = @{ Class = 'LOCAL_MUTATION'; Info = 'Write artifacts/role-assignment-proposal.json (assignment is not executed)'; Run = { Add-Results (Prepare-RoleAssignment) } }
    PrepareBuildingBootstrap = @{ Class = 'READ_ONLY'; Info = 'Validate the bootstrap manifest status'; Run = { Add-Results (Prepare-BuildingBootstrap) } }
    VerifyLiveRead = @{ Class = 'READ_ONLY'; Info = 'Prerequisite readiness for the live-read test (never reports success without evidence)'; Run = { Add-Results (Verify-LiveRead) } }
    VerifyLiveWrite = @{ Class = 'READ_ONLY'; Info = 'Evidence status for Places writes (NOT_TESTED until authorized writes exist)'; Run = { Add-Results (Verify-LiveWrite) } }
}

function Show-Help {
    "PlaceHub requirements - usage: pwsh scripts/Invoke-PlaceHub-Requirements.ps1 <Command> [-Environment development] [-DockerProfile Live|Synthetic] [-ReportDirectory <path>]"
    ''
    'Classes: ' + ((Get-RequirementsActionClasses) -join ', ') + ' (this script implements no TENANT, PRIVILEGED or DESTRUCTIVE command)'
    'There is no -Force or -AutoApprove. Privileged work needs: exact environment, change reference, target, operation name, approval evidence, confirmed effective permissions and a matching tenant.'
    ''
    foreach ($k in $Commands.Keys) { '{0,-26} {1,-15} {2}' -f $k, $Commands[$k].Class, $Commands[$k].Info }
    ''
    'Exit codes: ' + (((Get-RequirementsExitCodes).GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')
}

$codes = Get-RequirementsExitCodes
try {
    if (-not $Commands.Contains($Command)) { Stop-Requirements -Exit VALIDATION_FAILED -Message "UNKNOWN_COMMAND: $Command (run Help)" }
    $entry = $Commands[$Command]
    Assert-ActionAuthorized -Class $entry.Class -ActionName $Command -Environment $Environment -ChangeReference $ChangeReference -TargetIdentity $TargetIdentity -Operation $Operation -ApprovalEvidencePath $ApprovalEvidencePath -EffectivePermissionsConfirmed:$EffectivePermissionsConfirmed
    if ($Command -eq 'Help') { Show-Help; exit $codes.SUCCESS }
    if ($Environment -ne 'development') { Stop-Requirements -Exit SECURITY_BLOCKED -Message 'ENVIRONMENT_NOT_AUTHORIZED' }
    & $entry.Run
    $reportable = @($script:Collected)
    $paths = Write-RequirementsReport -Results $reportable -Directory $ReportDirectory -Command $Command -Environment $Environment
    foreach ($r in $reportable) { '{0,-12} {1,-40} {2}' -f $r.status, $r.check, $r.detail }
    "Report: $($paths.Json)"
    if (@($reportable | Where-Object status -eq 'FAIL').Count -gt 0) { exit $codes.VALIDATION_FAILED }
    if ($Command -like 'Check*' -and @($reportable | Where-Object { $_.status -eq 'BLOCKED' -and $_.check -match 'azure.login|tenant.binding' }).Count -gt 0) { exit $codes.AUTHENTICATION_REQUIRED }
    exit $codes.SUCCESS
}
catch {
    $name = if ($_.Exception.PSObject.Properties['ExitName']) { $_.Exception.ExitName } else { 'EXECUTION_FAILED' }
    [Console]::Error.WriteLine("$name`: $(Protect-Text $_.Exception.Message)")
    exit $codes[$name]
}
