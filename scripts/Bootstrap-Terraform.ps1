#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$EnvFile = (Join-Path $PSScriptRoot '..\.env'), [string]$TenantId, [string]$SubscriptionId,
    [string]$Repository, [string]$Environment, [string]$Location, [string]$StateResourceGroup,
    [string]$StateStorageAccount, [string]$StateContainer, [string]$StateKey, [string]$DeploymentAppName,
    [string]$ConfirmTarget, [switch]$DryRun, [switch]$SkipGitHubConfiguration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = $VerbosePreference = $DebugPreference = 'SilentlyContinue'
$script:AllowedFailureCategories = @('PREREQUISITE_FAILED','AUTHENTICATION_FAILED','AUTHORIZATION_FAILED','CONFIGURATION_INVALID','RESOURCE_CONFLICT','OIDC_VALIDATION_FAILED')

function Stop-Safe {
    param(
        [Parameter(Mandatory)][ValidateSet('PREREQUISITE_FAILED','AUTHENTICATION_FAILED','AUTHORIZATION_FAILED','CONFIGURATION_INVALID','RESOURCE_CONFLICT','OIDC_VALIDATION_FAILED')][string]$Category,
        [int]$NativeExitCode = -1
    )
    $exception = [InvalidOperationException]::new('Bootstrap operation failed.')
    $exception.Data['SafeCategory'] = $Category
    $exception.Data['NativeExitCode'] = $NativeExitCode
    throw $exception
}

function Write-SafeStatus {
    param([Parameter(Mandatory)][ValidateSet('PREREQUISITES_OK','AUTHENTICATION_OK','TARGET_CONFIRMED','DISCOVERY_OK','PREVIEW_COMPLETE','BOOTSTRAP_COMPLETE','GRAPH_PERMISSIONS_UNCHANGED')][string]$Status)
    [Console]::Out.WriteLine($Status)
}

function Read-DotEnv {
    param([string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -notmatch '^[A-Za-z_][A-Za-z0-9_]*=') { Stop-Safe 'CONFIGURATION_INVALID' }
        $name, $value = $trimmed -split '=', 2
        $value = $value.Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) { $value = $value.Substring(1, $value.Length - 2) }
        $values[$name] = $value
    }
    $values
}

function Resolve-Value([string]$Current, [hashtable]$Values, [string]$Name) {
    if ($Current) { return $Current }
    if ($Values.ContainsKey($Name)) { return [string]$Values[$Name] }
    Stop-Safe 'CONFIGURATION_INVALID'
}

function Assert-Command([string]$Name, [switch]$Optional) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue) -and -not $Optional) { Stop-Safe 'PREREQUISITE_FAILED' }
}

function Invoke-SafeCommand {
    param(
        [Parameter(Mandatory)][string]$File, [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][ValidateSet('PREREQUISITE_FAILED','AUTHENTICATION_FAILED','AUTHORIZATION_FAILED','CONFIGURATION_INVALID','RESOURCE_CONFLICT','OIDC_VALIDATION_FAILED')][string]$FailureCategory,
        [ValidateSet('None','Text','Json')][string]$OutputMode = 'None', [switch]$Mutating, [switch]$AllowFailure
    )
    if ($Mutating -and ($DryRun -or -not $PSCmdlet.ShouldProcess('bootstrap resource', 'perform approved mutation'))) {
        return [pscustomobject]@{ Executed=$false; ExitCode=0; Succeeded=$true; Data=$null }
    }
    # Native output stays in memory and is never emitted or included in an exception.
    $nativeOutput = & $File @Arguments 2>&1
    $nativeExitCode = $LASTEXITCODE
    if ($nativeExitCode -ne 0) {
        $nativeOutput = $null
        if ($AllowFailure) { return [pscustomobject]@{ Executed=$true; ExitCode=$nativeExitCode; Succeeded=$false; Data=$null } }
        Stop-Safe $FailureCategory $nativeExitCode
    }
    $data = $null
    if ($OutputMode -eq 'Text') { $data = ($nativeOutput -join "`n") }
    elseif ($OutputMode -eq 'Json') {
        try { $data = (($nativeOutput -join "`n") | ConvertFrom-Json) }
        catch { $nativeOutput = $null; Stop-Safe $FailureCategory }
    }
    $nativeOutput = $null
    [pscustomobject]@{ Executed=$true; ExitCode=$nativeExitCode; Succeeded=$true; Data=$data }
}

function Invoke-AzJson {
    param([string[]]$Arguments, [string]$FailureCategory, [switch]$AllowFailure)
    Invoke-SafeCommand 'az' ($Arguments + @('--output','json','--only-show-errors')) $FailureCategory 'Json' -AllowFailure:$AllowFailure
}

function Invoke-Mutation {
    param([string]$File, [string[]]$Arguments, [string]$FailureCategory, [ValidateSet('None','Json')][string]$OutputMode = 'None')
    Invoke-SafeCommand $File $Arguments $FailureCategory $OutputMode -Mutating
}

try {
    $dotenv = Read-DotEnv $EnvFile
    $TenantId = Resolve-Value $TenantId $dotenv 'AZURE_TENANT_ID'; $SubscriptionId = Resolve-Value $SubscriptionId $dotenv 'AZURE_SUBSCRIPTION_ID'
    $Repository = Resolve-Value $Repository $dotenv 'GITHUB_REPOSITORY'; $Environment = Resolve-Value $Environment $dotenv 'TF_ENVIRONMENT'
    $Location = Resolve-Value $Location $dotenv 'AZURE_LOCATION'; $StateResourceGroup = Resolve-Value $StateResourceGroup $dotenv 'TF_STATE_RG'
    $StateStorageAccount = Resolve-Value $StateStorageAccount $dotenv 'TF_STATE_STORAGE'; $StateContainer = Resolve-Value $StateContainer $dotenv 'TF_STATE_CONTAINER'
    $StateKey = Resolve-Value $StateKey $dotenv 'TF_STATE_KEY'; $DeploymentAppName = Resolve-Value $DeploymentAppName $dotenv 'TF_DEPLOYMENT_APP_NAME'
    if ($TenantId -notmatch '^[0-9a-fA-F-]{36}$' -or $SubscriptionId -notmatch '^[0-9a-fA-F-]{36}$' -or $Repository -notmatch '^[^/\s]+/[^/\s]+$' -or $StateStorageAccount -notmatch '^[a-z0-9]{3,24}$' -or $Environment -notmatch '^[A-Za-z0-9_.-]+$') { Stop-Safe 'CONFIGURATION_INVALID' }

    Assert-Command 'pwsh'; Assert-Command 'az'; Assert-Command 'gh'; Assert-Command 'terraform'; Assert-Command 'python' -Optional
    Write-SafeStatus 'PREREQUISITES_OK'
    $target = "$TenantId/$SubscriptionId/$Repository/$Environment"
    if (-not $ConfirmTarget) { $ConfirmTarget = Read-Host 'Enter the pre-approved target confirmation value' }
    if ($ConfirmTarget -cne $target) { Stop-Safe 'CONFIGURATION_INVALID' }
    Write-SafeStatus 'TARGET_CONFIRMED'

    $account = Invoke-AzJson @('account','show') 'AUTHENTICATION_FAILED'
    if ($account.Data.tenantId -ne $TenantId) { Stop-Safe 'AUTHENTICATION_FAILED' }
    $subscription = Invoke-AzJson @('account','show','--subscription',$SubscriptionId) 'AUTHORIZATION_FAILED'
    if ($subscription.Data.tenantId -ne $TenantId) { Stop-Safe 'AUTHORIZATION_FAILED' }
    $null = Invoke-SafeCommand 'gh' @('auth','status') 'AUTHENTICATION_FAILED'
    $repo = Invoke-SafeCommand 'gh' @('repo','view',$Repository,'--json','nameWithOwner','--jq','.nameWithOwner') 'AUTHORIZATION_FAILED' 'Text'
    if ($repo.Data.Trim().ToLowerInvariant() -ne $Repository.ToLowerInvariant()) { Stop-Safe 'AUTHORIZATION_FAILED' }
    Write-SafeStatus 'AUTHENTICATION_OK'

    $subscriptionScope = "/subscriptions/$SubscriptionId"; $stateRgScope = "$subscriptionScope/resourceGroups/$StateResourceGroup"
    $storageScope = "$stateRgScope/providers/Microsoft.Storage/storageAccounts/$StateStorageAccount"; $containerScope = "$storageScope/blobServices/default/containers/$StateContainer"
    $workloadRg = "rg-placehub-$($Environment.ToLowerInvariant())"; $workloadScope = "$subscriptionScope/resourceGroups/$workloadRg"
    $expectedIssuer = 'https://token.actions.githubusercontent.com'; $expectedSubject = "repo:$Repository:environment:$Environment"; $expectedAudience = 'api://AzureADTokenExchange'
    $ficName = "github-$($Environment.ToLowerInvariant() -replace '[^a-z0-9-]','-')"

    $rg = Invoke-AzJson @('group','show','--name',$StateResourceGroup,'--subscription',$SubscriptionId) 'AUTHORIZATION_FAILED' -AllowFailure
    $storage = Invoke-AzJson @('storage','account','show','--name',$StateStorageAccount,'--resource-group',$StateResourceGroup,'--subscription',$SubscriptionId) 'AUTHORIZATION_FAILED' -AllowFailure
    $workload = Invoke-AzJson @('group','show','--name',$workloadRg,'--subscription',$SubscriptionId) 'AUTHORIZATION_FAILED' -AllowFailure
    $apps = @((Invoke-AzJson @('ad','app','list','--display-name',$DeploymentAppName,'--filter',"displayName eq '$DeploymentAppName'") 'AUTHORIZATION_FAILED').Data)
    if ($apps.Count -gt 1) { Stop-Safe 'RESOURCE_CONFLICT' }
    $changesRequired = -not ($rg.Succeeded -and $storage.Succeeded -and $workload.Succeeded)
    $app = if ($apps.Count -eq 1) { $apps[0] } else { $null }; $credentialExists = $false
    if ($app) {
        $ficUrl = "https://graph.microsoft.com/v1.0/applications/$($app.id)/federatedIdentityCredentials"
        $named = @((Invoke-AzJson @('rest','--method','get','--url',$ficUrl) 'AUTHORIZATION_FAILED').Data.value | Where-Object name -eq $ficName)
        if ($named.Count -gt 1) { Stop-Safe 'RESOURCE_CONFLICT' }
        if ($named.Count -eq 1) {
            $audiences = @($named[0].audiences)
            if ($named[0].issuer -cne $expectedIssuer -or $named[0].subject -cne $expectedSubject -or $audiences.Count -ne 1 -or $audiences[0] -cne $expectedAudience) { Stop-Safe 'OIDC_VALIDATION_FAILED' }
            $credentialExists = $true
        } else { $changesRequired = $true }
    } else { $changesRequired = $true }
    Write-SafeStatus 'DISCOVERY_OK'

    if ($DryRun -or [bool]$WhatIfPreference) {
        Write-SafeStatus 'PREVIEW_COMPLETE'; Write-SafeStatus 'GRAPH_PERMISSIONS_UNCHANGED'; return
    }

    if (-not $rg.Succeeded) { if (-not (Invoke-Mutation 'az' @('group','create','--name',$StateResourceGroup,'--location',$Location,'--subscription',$SubscriptionId,'--output','none','--only-show-errors') 'AUTHORIZATION_FAILED').Executed) { Stop-Safe 'CONFIGURATION_INVALID' } }
    if (-not $storage.Succeeded) { if (-not (Invoke-Mutation 'az' @('storage','account','create','--name',$StateStorageAccount,'--resource-group',$StateResourceGroup,'--location',$Location,'--sku','Standard_LRS','--kind','StorageV2','--min-tls-version','TLS1_2','--allow-blob-public-access','false','--allow-shared-key-access','false','--https-only','true','--subscription',$SubscriptionId,'--output','none','--only-show-errors') 'AUTHORIZATION_FAILED').Executed) { Stop-Safe 'CONFIGURATION_INVALID' } }
    $containerApi = "https://management.azure.com$containerScope?api-version=2023-05-01"
    $null = Invoke-Mutation 'az' @('rest','--method','put','--url',$containerApi,'--body','{"properties":{"publicAccess":"None"}}','--output','none','--only-show-errors') 'AUTHORIZATION_FAILED'
    $null = Invoke-Mutation 'az' @('storage','account','blob-service-properties','update','--account-name',$StateStorageAccount,'--resource-group',$StateResourceGroup,'--enable-versioning','true','--enable-delete-retention','true','--delete-retention-days','30','--enable-container-delete-retention','true','--container-delete-retention-days','30','--subscription',$SubscriptionId,'--output','none','--only-show-errors') 'AUTHORIZATION_FAILED'

    if (-not $app) {
        $created = Invoke-Mutation 'az' @('ad','app','create','--display-name',$DeploymentAppName,'--sign-in-audience','AzureADMyOrg','--output','json','--only-show-errors') 'AUTHORIZATION_FAILED' 'Json'
        if (-not $created.Executed -or -not $created.Data) { Stop-Safe 'CONFIGURATION_INVALID' }; $app = $created.Data
    }
    $clientId = $app.appId; $appObjectId = $app.id
    $servicePrincipals = @((Invoke-AzJson @('ad','sp','list','--filter',"appId eq '$clientId'") 'AUTHORIZATION_FAILED').Data)
    if ($servicePrincipals.Count -gt 1) { Stop-Safe 'RESOURCE_CONFLICT' }
    if ($servicePrincipals.Count -eq 0) {
        $createdSp = Invoke-Mutation 'az' @('ad','sp','create','--id',$clientId,'--output','json','--only-show-errors') 'AUTHORIZATION_FAILED' 'Json'
        if (-not $createdSp.Executed -or -not $createdSp.Data) { Stop-Safe 'CONFIGURATION_INVALID' }; $servicePrincipal = $createdSp.Data
    } else { $servicePrincipal = $servicePrincipals[0] }

    if (-not $credentialExists) {
        $ficBody = @{name=$ficName;issuer=$expectedIssuer;subject=$expectedSubject;audiences=@($expectedAudience);description='PlaceHub Terraform GitHub environment trust'} | ConvertTo-Json -Compress
        $ficUrl = "https://graph.microsoft.com/v1.0/applications/$appObjectId/federatedIdentityCredentials"
        $null = Invoke-Mutation 'az' @('rest','--method','post','--url',$ficUrl,'--body',$ficBody,'--headers','Content-Type=application/json','--output','none','--only-show-errors') 'AUTHORIZATION_FAILED'
        $verified = @((Invoke-AzJson @('rest','--method','get','--url',$ficUrl) 'OIDC_VALIDATION_FAILED').Data.value | Where-Object name -eq $ficName)
        if ($verified.Count -ne 1 -or $verified[0].issuer -cne $expectedIssuer -or $verified[0].subject -cne $expectedSubject -or @($verified[0].audiences).Count -ne 1 -or @($verified[0].audiences)[0] -cne $expectedAudience) { Stop-Safe 'OIDC_VALIDATION_FAILED' }
    }

    if (-not $workload.Succeeded) { $null = Invoke-Mutation 'az' @('group','create','--name',$workloadRg,'--location',$Location,'--subscription',$SubscriptionId,'--output','none','--only-show-errors') 'AUTHORIZATION_FAILED' }
    $null = Invoke-Mutation 'az' @('role','assignment','create','--assignee-object-id',$servicePrincipal.id,'--assignee-principal-type','ServicePrincipal','--role','Contributor','--scope',$workloadScope,'--output','none','--only-show-errors') 'AUTHORIZATION_FAILED'
    $null = Invoke-Mutation 'az' @('role','assignment','create','--assignee-object-id',$servicePrincipal.id,'--assignee-principal-type','ServicePrincipal','--role','Storage Blob Data Contributor','--scope',$containerScope,'--output','none','--only-show-errors') 'AUTHORIZATION_FAILED'
    if (-not $SkipGitHubConfiguration) {
        $null = Invoke-Mutation 'gh' @('api','--silent','--method','PUT',"repos/$Repository/environments/$Environment") 'AUTHORIZATION_FAILED'
        $variables = [ordered]@{AZURE_CLIENT_ID=$clientId;AZURE_TENANT_ID=$TenantId;AZURE_SUBSCRIPTION_ID=$SubscriptionId;TF_STATE_RG=$StateResourceGroup;TF_STATE_STORAGE=$StateStorageAccount;TF_STATE_CONTAINER=$StateContainer;TF_STATE_KEY=$StateKey;TF_ENVIRONMENT=$Environment}
        foreach ($entry in $variables.GetEnumerator()) { $null = Invoke-Mutation 'gh' @('variable','set',$entry.Key,'--body',[string]$entry.Value,'--env',$Environment,'--repo',$Repository) 'AUTHORIZATION_FAILED' }
    }
    Write-SafeStatus 'BOOTSTRAP_COMPLETE'; Write-SafeStatus 'GRAPH_PERMISSIONS_UNCHANGED'
}
catch {
    $category = if ($_.Exception.Data.Contains('SafeCategory') -and $script:AllowedFailureCategories -contains $_.Exception.Data['SafeCategory']) { [string]$_.Exception.Data['SafeCategory'] } else { 'CONFIGURATION_INVALID' }
    [Console]::Error.WriteLine("${category}: FAILED")
    exit 1
}
