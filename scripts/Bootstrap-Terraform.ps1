#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$EnvFile = (Join-Path $PSScriptRoot '..\.env'),
    [string]$TenantId,
    [string]$SubscriptionId,
    [string]$Repository,
    [string]$Environment,
    [string]$Location,
    [string]$StateResourceGroup,
    [string]$StateStorageAccount,
    [string]$StateContainer,
    [string]$StateKey,
    [string]$DeploymentAppName,
    [string]$ConfirmTarget,
    [switch]$DryRun,
    [switch]$SkipGitHubConfiguration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Read-DotEnv {
    param([string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -notmatch '^[A-Za-z_][A-Za-z0-9_]*=') { throw "Invalid .env entry (expected NAME=value): $trimmed" }
        $name, $value = $trimmed -split '=', 2
        $value = $value.Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$name] = $value
    }
    return $values
}

function Resolve-Value([string]$Current, [hashtable]$Values, [string]$Name) {
    if ($Current) { return $Current }
    if ($Values.ContainsKey($Name)) { return [string]$Values[$Name] }
    throw "Missing required value $Name. Supply it as a parameter or in the local .env file."
}

function Assert-Command([string]$Name, [switch]$Optional) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command -and -not $Optional) { throw "Required command '$Name' was not found on PATH." }
    if ($command) { Write-Verbose "${Name}: $(& $Name --version 2>&1 | Select-Object -First 1)" }
}

function Invoke-External {
    param([Parameter(Mandatory)][string]$File, [Parameter(Mandatory)][string[]]$Arguments, [switch]$Mutating)
    $display = "$File $($Arguments -join ' ')"
    if ($Mutating -and ($DryRun -or -not $PSCmdlet.ShouldProcess($display, 'Execute'))) {
        Write-Host "DRY-RUN: $display"
        return $null
    }
    $output = & $File @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $display`n$($output -join "`n")" }
    return ($output -join "`n")
}

function Invoke-AzJson([string[]]$Arguments) {
    $raw = Invoke-External -File az -Arguments ($Arguments + @('--output', 'json', '--only-show-errors'))
    if (-not $raw) { return $null }
    return $raw | ConvertFrom-Json
}

function Find-AzJson([string[]]$Arguments) {
    $raw = & az @Arguments --output json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
    return (($raw -join "`n") | ConvertFrom-Json)
}

$dotenv = Read-DotEnv $EnvFile
$TenantId = Resolve-Value $TenantId $dotenv 'AZURE_TENANT_ID'
$SubscriptionId = Resolve-Value $SubscriptionId $dotenv 'AZURE_SUBSCRIPTION_ID'
$Repository = Resolve-Value $Repository $dotenv 'GITHUB_REPOSITORY'
$Environment = Resolve-Value $Environment $dotenv 'TF_ENVIRONMENT'
$Location = Resolve-Value $Location $dotenv 'AZURE_LOCATION'
$StateResourceGroup = Resolve-Value $StateResourceGroup $dotenv 'TF_STATE_RG'
$StateStorageAccount = Resolve-Value $StateStorageAccount $dotenv 'TF_STATE_STORAGE'
$StateContainer = Resolve-Value $StateContainer $dotenv 'TF_STATE_CONTAINER'
$StateKey = Resolve-Value $StateKey $dotenv 'TF_STATE_KEY'
$DeploymentAppName = Resolve-Value $DeploymentAppName $dotenv 'TF_DEPLOYMENT_APP_NAME'

if ($TenantId -notmatch '^[0-9a-fA-F-]{36}$' -or $SubscriptionId -notmatch '^[0-9a-fA-F-]{36}$') { throw 'Tenant and subscription IDs must be GUIDs.' }
if ($Repository -notmatch '^[^/\s]+/[^/\s]+$') { throw 'Repository must use owner/name format.' }
if ($StateStorageAccount -notmatch '^[a-z0-9]{3,24}$') { throw 'Storage account name must be 3-24 lowercase letters or digits.' }
if ($Environment -notmatch '^[A-Za-z0-9_.-]+$') { throw 'Environment contains unsupported characters.' }

Assert-Command pwsh
Assert-Command az
Assert-Command gh
Assert-Command terraform
Assert-Command python -Optional

$target = "$TenantId/$SubscriptionId/$Repository/$Environment"
if (-not $ConfirmTarget) { $ConfirmTarget = Read-Host "Type the exact target to continue: $target" }
if ($ConfirmTarget -cne $target) { throw 'Target confirmation did not match exactly; no changes were made.' }

$account = Invoke-AzJson @('account', 'show')
if ($account.tenantId -ne $TenantId) { throw "Azure CLI is authenticated to tenant $($account.tenantId), not $TenantId." }
$selected = Invoke-AzJson @('account', 'show', '--subscription', $SubscriptionId)
if ($selected.tenantId -ne $TenantId) { throw 'The selected subscription is not in the confirmed tenant.' }
$null = Invoke-External gh @('auth', 'status')
$ghRepo = Invoke-External gh @('repo', 'view', $Repository, '--json', 'nameWithOwner', '--jq', '.nameWithOwner')
if ($ghRepo.Trim().ToLowerInvariant() -ne $Repository.ToLowerInvariant()) { throw 'GitHub repository verification failed.' }

$subscriptionScope = "/subscriptions/$SubscriptionId"
$rgScope = "$subscriptionScope/resourceGroups/$StateResourceGroup"
$storageScope = "$rgScope/providers/Microsoft.Storage/storageAccounts/$StateStorageAccount"
$containerScope = "$storageScope/blobServices/default/containers/$StateContainer"

$rg = Find-AzJson @('group', 'show', '--name', $StateResourceGroup, '--subscription', $SubscriptionId)
if (-not $rg) { $null = Invoke-External az @('group','create','--name',$StateResourceGroup,'--location',$Location,'--subscription',$SubscriptionId,'--only-show-errors') -Mutating }

$storage = Find-AzJson @('storage','account','show','--name',$StateStorageAccount,'--resource-group',$StateResourceGroup,'--subscription',$SubscriptionId)
if (-not $storage) {
    $null = Invoke-External az @('storage','account','create','--name',$StateStorageAccount,'--resource-group',$StateResourceGroup,'--location',$Location,'--sku','Standard_LRS','--kind','StorageV2','--min-tls-version','TLS1_2','--allow-blob-public-access','false','--allow-shared-key-access','false','--https-only','true','--subscription',$SubscriptionId,'--only-show-errors') -Mutating
}
$containerApi = "https://management.azure.com$containerScope?api-version=2023-05-01"
$null = Invoke-External az @('rest','--method','put','--url',$containerApi,'--body','{"properties":{"publicAccess":"None"}}','--only-show-errors') -Mutating
$null = Invoke-External az @('storage','account','blob-service-properties','update','--account-name',$StateStorageAccount,'--resource-group',$StateResourceGroup,'--enable-versioning','true','--enable-delete-retention','true','--delete-retention-days','30','--enable-container-delete-retention','true','--container-delete-retention-days','30','--subscription',$SubscriptionId,'--only-show-errors') -Mutating

$apps = Invoke-AzJson @('ad','app','list','--display-name',$DeploymentAppName,'--filter',"displayName eq '$DeploymentAppName'")
if ($apps.Count -gt 1) { throw "Multiple app registrations named '$DeploymentAppName' exist; resolve ambiguity manually." }
if ($apps.Count -eq 0) {
    if ($DryRun) { $clientId = '<created-client-id>'; $appObjectId = '<created-object-id>' }
    else { $app = (Invoke-External az @('ad','app','create','--display-name',$DeploymentAppName,'--sign-in-audience','AzureADMyOrg','--only-show-errors') -Mutating) | ConvertFrom-Json; $clientId = $app.appId; $appObjectId = $app.id }
} else { $clientId = $apps[0].appId; $appObjectId = $apps[0].id }

if (-not $DryRun) {
    $sps = Invoke-AzJson @('ad','sp','list','--filter',"appId eq '$clientId'")
    if ($sps.Count -eq 0) { $sp = (Invoke-External az @('ad','sp','create','--id',$clientId,'--only-show-errors') -Mutating) | ConvertFrom-Json } else { $sp = $sps[0] }
    $spObjectId = $sp.id
    $subject = "repo:$Repository:environment:$Environment"
    $ficName = "github-$($Environment.ToLowerInvariant() -replace '[^a-z0-9-]','-')"
    $ficBody = @{ name=$ficName; issuer='https://token.actions.githubusercontent.com'; subject=$subject; audiences=@('api://AzureADTokenExchange'); description="PlaceHub Terraform GitHub environment $Environment" } | ConvertTo-Json -Compress
    $ficUrl = "https://graph.microsoft.com/v1.0/applications/$appObjectId/federatedIdentityCredentials"
    $existingFics = Invoke-AzJson @('rest','--method','get','--url',$ficUrl)
    $sameName = @($existingFics.value | Where-Object name -eq $ficName)
    if ($sameName.Count -and ($sameName[0].subject -ne $subject -or $sameName[0].issuer -ne 'https://token.actions.githubusercontent.com')) { throw 'An existing federated credential has the expected name but different trust values.' }
    if (-not $sameName.Count) { $null = Invoke-External az @('rest','--method','post','--url',$ficUrl,'--body',$ficBody,'--headers','Content-Type=application/json','--only-show-errors') -Mutating }

    # Contributor is deliberately limited to the approved workload resource group, not subscription scope.
    $workloadRg = "rg-placehub-$($Environment.ToLowerInvariant())"
    $workloadScope = "$subscriptionScope/resourceGroups/$workloadRg"
    $workload = Find-AzJson @('group','show','--name',$workloadRg,'--subscription',$SubscriptionId)
    if (-not $workload) { $null = Invoke-External az @('group','create','--name',$workloadRg,'--location',$Location,'--subscription',$SubscriptionId,'--only-show-errors') -Mutating }
    $null = Invoke-External az @('role','assignment','create','--assignee-object-id',$spObjectId,'--assignee-principal-type','ServicePrincipal','--role','Contributor','--scope',$workloadScope,'--only-show-errors') -Mutating
    $null = Invoke-External az @('role','assignment','create','--assignee-object-id',$spObjectId,'--assignee-principal-type','ServicePrincipal','--role','Storage Blob Data Contributor','--scope',$containerScope,'--only-show-errors') -Mutating

    if (-not $SkipGitHubConfiguration) {
        $null = Invoke-External gh @('api','--method','PUT',"repos/$Repository/environments/$Environment") -Mutating
        $variables = [ordered]@{ AZURE_CLIENT_ID=$clientId; AZURE_TENANT_ID=$TenantId; AZURE_SUBSCRIPTION_ID=$SubscriptionId; TF_STATE_RG=$StateResourceGroup; TF_STATE_STORAGE=$StateStorageAccount; TF_STATE_CONTAINER=$StateContainer; TF_STATE_KEY=$StateKey; TF_ENVIRONMENT=$Environment }
        foreach ($entry in $variables.GetEnumerator()) { $null = Invoke-External gh @('variable','set',$entry.Key,'--body',[string]$entry.Value,'--env',$Environment,'--repo',$Repository) -Mutating }
    }
} else { $subject = "repo:$Repository:environment:$Environment"; $spObjectId = '<created-service-principal-object-id>' }

[pscustomobject]@{
    TenantId=$TenantId; SubscriptionId=$SubscriptionId; Repository=$Repository; Environment=$Environment
    StateResourceGroup=$StateResourceGroup; StateStorageAccount=$StateStorageAccount; StateContainer=$StateContainer; StateKey=$StateKey
    DeploymentClientId=$clientId; DeploymentServicePrincipalObjectId=$spObjectId
    OidcIssuer='https://token.actions.githubusercontent.com'; OidcSubject=$subject; OidcAudience='api://AzureADTokenExchange'
    GraphAdminConsentGranted=$false; SecretsCreated=$false; DryRun=[bool]$DryRun
} | Format-List

Write-Warning 'No Microsoft Graph application permission, admin consent, Exchange permission, or GitHub reviewer protection was granted. See docs/terraform-bootstrap.md.'

