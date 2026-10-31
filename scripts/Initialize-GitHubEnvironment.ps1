#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string]$Repository = 'JoergBrors/PlaceHub',
    [string]$Environment = 'development',
    [string]$DeploymentBranch = 'main',
    [string[]]$Reviewers,
    [switch]$Apply,
    [string]$ConfirmTarget,
    [Parameter(DontShow)][string]$GitHubCli = 'gh'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = $VerbosePreference = $DebugPreference = 'SilentlyContinue'
$script:FailureCategories = @('PREREQUISITE_FAILED','AUTHENTICATION_FAILED','AUTHORIZATION_FAILED','CONFIGURATION_INVALID','API_FAILED','RESOURCE_CONFLICT','PROTECTION_UNSUPPORTED','PROTECTION_WEAKENING_BLOCKED')
$script:ApiVersion = '2026-03-10'

function Stop-Safe {
    param(
        [Parameter(Mandatory)][ValidateSet('PREREQUISITE_FAILED','AUTHENTICATION_FAILED','AUTHORIZATION_FAILED','CONFIGURATION_INVALID','API_FAILED','RESOURCE_CONFLICT','PROTECTION_UNSUPPORTED','PROTECTION_WEAKENING_BLOCKED')][string]$Category,
        [int]$NativeExitCode = -1
    )
    $exception = [InvalidOperationException]::new('GitHub Environment operation failed.')
    $exception.Data['SafeCategory'] = $Category
    $exception.Data['NativeExitCode'] = $NativeExitCode
    throw $exception
}

function Write-SafeStatus {
    param([Parameter(Mandatory)][ValidateSet('PREREQUISITES_OK','AUTHENTICATION_OK','ADMIN_PERMISSION_OK','ENVIRONMENT_FOUND','ENVIRONMENT_MISSING','REVIEWERS_VALIDATED','PROTECTION_SUPPORTED','ENVIRONMENT_COMPLIANT','PREVIEW_CHANGES_REQUIRED','APPLY_COMPLETE')][string]$Status)
    [Console]::Out.WriteLine($Status)
}

function Invoke-SafeCommand {
    param(
        [string]$File, [string[]]$Arguments, [string]$FailureCategory,
        [ValidateSet('None','Text','Json')][string]$OutputMode = 'None',
        [string]$InputText, [switch]$AllowFailure, [switch]$Mutating
    )
    if ($Mutating -and (-not $Apply -or -not $PSCmdlet.ShouldProcess('GitHub Environment configuration', 'apply approved configuration'))) {
        return [pscustomobject]@{ Executed=$false; Succeeded=$true; ExitCode=0; Data=$null }
    }
    $nativeOutput = if ($PSBoundParameters.ContainsKey('InputText')) { $InputText | & $File @Arguments 2>&1 } else { & $File @Arguments 2>&1 }
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $failureData = if ($AllowFailure) { ($nativeOutput -join "`n") } else { $null }
        $nativeOutput = $null
        if ($AllowFailure) { return [pscustomobject]@{ Executed=$true; Succeeded=$false; ExitCode=$exitCode; Data=$failureData } }
        Stop-Safe $FailureCategory $exitCode
    }
    $data = $null
    if ($OutputMode -eq 'Text') { $data = ($nativeOutput -join "`n") }
    elseif ($OutputMode -eq 'Json') {
        try { $data = (($nativeOutput -join "`n") | ConvertFrom-Json) } catch { $nativeOutput=$null; Stop-Safe $FailureCategory }
    }
    $nativeOutput = $null
    [pscustomobject]@{ Executed=$true; Succeeded=$true; ExitCode=$exitCode; Data=$data }
}

function Invoke-GhApi {
    param(
        [string]$Endpoint, [string]$Method = 'GET', [ValidateSet('None','Text','Json')][string]$OutputMode = 'Json',
        [string]$Body, [switch]$AllowFailure, [switch]$Mutating
    )
    $arguments = @('api',$Endpoint,'--method',$Method,'--header','Accept: application/vnd.github+json','--header',"X-GitHub-Api-Version: $script:ApiVersion")
    if ($PSBoundParameters.ContainsKey('Body')) { $arguments += @('--input','-') }
    if ($OutputMode -eq 'None') { $arguments += '--silent' }
    Invoke-SafeCommand $GitHubCli $arguments 'API_FAILED' $OutputMode -InputText:$Body -AllowFailure:$AllowFailure -Mutating:$Mutating
}

function ConvertTo-ReviewerSet {
    param([object[]]$ReviewerObjects)
    @($ReviewerObjects | ForEach-Object { "$($_.type):$($_.id)" } | Sort-Object -Unique)
}

try {
    if ($PSVersionTable.PSVersion.Major -lt 7 -or -not (Get-Command $GitHubCli -ErrorAction SilentlyContinue)) { Stop-Safe 'PREREQUISITE_FAILED' }
    if ($Repository -notmatch '^[^/\s]+/[^/\s]+$' -or $Environment -notmatch '^[A-Za-z0-9_.-]+$' -or $DeploymentBranch -notmatch '^[A-Za-z0-9._/-]+$') { Stop-Safe 'CONFIGURATION_INVALID' }
    $reviewersSpecified = $null -ne $Reviewers -and $Reviewers.Count -gt 0
    if ($reviewersSpecified -and $Reviewers.Count -gt 6) { Stop-Safe 'CONFIGURATION_INVALID' }
    Write-SafeStatus 'PREREQUISITES_OK'

    $null = Invoke-SafeCommand $GitHubCli @('auth','status') 'AUTHENTICATION_FAILED'
    Write-SafeStatus 'AUTHENTICATION_OK'

    $repoEndpoint = "repos/$Repository"
    $repositoryResult = Invoke-GhApi $repoEndpoint
    if (-not [bool]$repositoryResult.Data.permissions.admin) { Stop-Safe 'AUTHORIZATION_FAILED' }
    $visibility = [string]$repositoryResult.Data.visibility
    $ownerLogin = [string]$repositoryResult.Data.owner.login
    $ownerType = [string]$repositoryResult.Data.owner.type
    Write-SafeStatus 'ADMIN_PERMISSION_OK'

    $encodedEnvironment = [uri]::EscapeDataString($Environment)
    $environmentEndpoint = "repos/$Repository/environments/$encodedEnvironment"
    $environmentResult = Invoke-GhApi $environmentEndpoint -AllowFailure
    $environmentExists = $environmentResult.Succeeded
    if (-not $environmentExists -and [string]$environmentResult.Data -notmatch '(?i)HTTP[^\r\n]*\s404\b|status.?\s*404') { Stop-Safe 'API_FAILED' }
    if ($environmentExists) { Write-SafeStatus 'ENVIRONMENT_FOUND' } else { Write-SafeStatus 'ENVIRONMENT_MISSING' }

    $ownerPlanName = $null
    if (-not $environmentExists -and $visibility -ne 'public') {
        $ownerEndpoint = if ($ownerType -eq 'Organization') { "orgs/$ownerLogin" } else { "users/$ownerLogin" }
        $ownerPlanName = [string](Invoke-GhApi $ownerEndpoint).Data.plan.name
        if ($ownerPlanName -match '(?i)^(free|bronze|silver|gold)$' -or ($visibility -eq 'internal' -and $ownerPlanName -notmatch '(?i)enterprise|business')) { Stop-Safe 'PROTECTION_UNSUPPORTED' }
    }

    $existingWaitTimer = 0
    $existingPreventSelfReview = $false
    $existingReviewers = @()
    $existingCustomPolicies = $false
    $existingProtectedBranches = $false
    if ($environmentExists) {
        $existingCustomPolicies = [bool]$environmentResult.Data.deployment_branch_policy.custom_branch_policies
        $existingProtectedBranches = [bool]$environmentResult.Data.deployment_branch_policy.protected_branches
        foreach ($rule in @($environmentResult.Data.protection_rules)) {
            if ($rule.type -eq 'wait_timer') { $existingWaitTimer = [int]$rule.wait_timer }
            if ($rule.type -eq 'required_reviewers') {
                $existingPreventSelfReview = [bool]$rule.prevent_self_review
                $existingReviewers = @($rule.reviewers | ForEach-Object { [pscustomobject]@{ type=[string]$_.type; id=[long]$_.reviewer.id } })
            }
        }
    }

    $desiredReviewers = @($existingReviewers)
    $desiredPreventSelfReview = $existingPreventSelfReview
    if ($reviewersSpecified) {
        if ($visibility -ne 'public') {
            if (-not $ownerPlanName) {
                $ownerEndpoint = if ($ownerType -eq 'Organization') { "orgs/$ownerLogin" } else { "users/$ownerLogin" }
                $ownerPlanName = [string](Invoke-GhApi $ownerEndpoint).Data.plan.name
            }
            if ($ownerPlanName -notmatch '(?i)enterprise|business') { Stop-Safe 'PROTECTION_UNSUPPORTED' }
        }
        $resolved = @()
        foreach ($reviewerSpec in @($Reviewers | Sort-Object -Unique)) {
            if ($reviewerSpec -match '^team:([^/]+)/(.+)$') {
                if ($ownerType -ne 'Organization' -or $Matches[1] -cne $ownerLogin) { Stop-Safe 'CONFIGURATION_INVALID' }
                $team = (Invoke-GhApi "orgs/$($Matches[1])/teams/$([uri]::EscapeDataString($Matches[2]))").Data
                $access = Invoke-GhApi "orgs/$($Matches[1])/teams/$([uri]::EscapeDataString($Matches[2]))/repos/$Repository" -AllowFailure
                if (-not $access.Succeeded) { Stop-Safe 'AUTHORIZATION_FAILED' }
                $resolved += [pscustomobject]@{ type='Team'; id=[long]$team.id }
            } else {
                $login = if ($reviewerSpec -match '^user:(.+)$') { $Matches[1] } else { $reviewerSpec }
                if ($login -notmatch '^[A-Za-z0-9-]+$') { Stop-Safe 'CONFIGURATION_INVALID' }
                $user = (Invoke-GhApi "users/$login").Data
                $access = (Invoke-GhApi "repos/$Repository/collaborators/$login/permission").Data
                if ([string]$access.permission -notin @('read','triage','write','maintain','admin')) { Stop-Safe 'AUTHORIZATION_FAILED' }
                $resolved += [pscustomobject]@{ type='User'; id=[long]$user.id }
            }
        }
        $desiredReviewers = @($resolved | Sort-Object type,id -Unique)
        if ($desiredReviewers.Count -gt 6) { Stop-Safe 'CONFIGURATION_INVALID' }
        if ($existingReviewers.Count -and (Compare-Object (ConvertTo-ReviewerSet $existingReviewers) (ConvertTo-ReviewerSet $desiredReviewers))) { Stop-Safe 'PROTECTION_WEAKENING_BLOCKED' }
        $desiredPreventSelfReview = $true
        Write-SafeStatus 'REVIEWERS_VALIDATED'
        Write-SafeStatus 'PROTECTION_SUPPORTED'
    }

    $branchPolicies = @()
    if ($environmentExists -and $existingCustomPolicies) {
        $policyResult = Invoke-GhApi "$environmentEndpoint/deployment-branch-policies?per_page=100"
        $branchPolicies = @($policyResult.Data.branch_policies)
    }
    $matchingBranches = @($branchPolicies | Where-Object { $_.type -eq 'branch' -and $_.name -ceq $DeploymentBranch })
    $unwantedPolicies = @($branchPolicies | Where-Object { -not ($_.type -eq 'branch' -and $_.name -ceq $DeploymentBranch) })
    $settingsChange = -not $environmentExists -or -not $existingCustomPolicies -or $existingProtectedBranches -or $matchingBranches.Count -ne 1 -or $unwantedPolicies.Count -gt 0
    if ($reviewersSpecified -and -not $existingPreventSelfReview) { $settingsChange = $true }

    if (-not $settingsChange) { Write-SafeStatus 'ENVIRONMENT_COMPLIANT'; return }
    if (-not $Apply -or [bool]$WhatIfPreference) { Write-SafeStatus 'PREVIEW_CHANGES_REQUIRED'; return }

    $expectedConfirmation = "$Repository/$Environment/$DeploymentBranch"
    if (-not $ConfirmTarget) { $ConfirmTarget = Read-Host 'Enter the pre-approved GitHub Environment target confirmation value' }
    if ($ConfirmTarget -cne $expectedConfirmation) { Stop-Safe 'CONFIGURATION_INVALID' }

    $payload = [ordered]@{
        wait_timer = $existingWaitTimer
        prevent_self_review = $desiredPreventSelfReview
        reviewers = @($desiredReviewers | ForEach-Object { @{ type=$_.type; id=$_.id } })
        deployment_branch_policy = @{ protected_branches=$false; custom_branch_policies=$true }
    } | ConvertTo-Json -Depth 6 -Compress
    $update = Invoke-GhApi $environmentEndpoint 'PUT' 'None' $payload -Mutating
    if (-not $update.Executed) { Stop-Safe 'CONFIGURATION_INVALID' }

    # Re-query after the update so creation and protected-branch transitions are handled idempotently.
    $policyResult = Invoke-GhApi "$environmentEndpoint/deployment-branch-policies?per_page=100"
    $branchPolicies = @($policyResult.Data.branch_policies)
    if (-not @($branchPolicies | Where-Object { $_.type -eq 'branch' -and $_.name -ceq $DeploymentBranch }).Count) {
        $branchPayload = @{ name=$DeploymentBranch; type='branch' } | ConvertTo-Json -Compress
        $null = Invoke-GhApi "$environmentEndpoint/deployment-branch-policies" 'POST' 'None' $branchPayload -Mutating
    }
    foreach ($policy in @($branchPolicies | Where-Object { -not ($_.type -eq 'branch' -and $_.name -ceq $DeploymentBranch) })) {
        $null = Invoke-GhApi "$environmentEndpoint/deployment-branch-policies/$($policy.id)" 'DELETE' 'None' -Mutating
    }
    Write-SafeStatus 'APPLY_COMPLETE'
}
catch {
    $category = if ($_.Exception.Data.Contains('SafeCategory') -and $script:FailureCategories -contains $_.Exception.Data['SafeCategory']) { [string]$_.Exception.Data['SafeCategory'] } else { 'CONFIGURATION_INVALID' }
    [Console]::Error.WriteLine("${category}: FAILED")
    exit 1
}
