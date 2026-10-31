#requires -Version 7.2
[CmdletBinding(DefaultParameterSetName = 'SavedPlan')]
param(
    [Parameter(Mandatory, ParameterSetName = 'SavedPlan')]
    [ValidateNotNullOrEmpty()]
    [string]$PlanPath,

    [Parameter(Mandatory, ParameterSetName = 'JsonFixture')]
    [ValidateNotNullOrEmpty()]
    [string]$PlanJsonPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Environment,

    [string]$GitHubOutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-PropertyValue {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-Array {
    param([object]$Value)
    if ($null -eq $Value) { return @() }
    return @($Value)
}

function ConvertTo-StableItem {
    param([object]$Value)
    return ($Value | ConvertTo-Json -Depth 40 -Compress)
}

function Test-CollectionRemoval {
    param([object]$Before, [object]$After, [string]$PropertyName)
    $beforeItems = Get-Array (Get-PropertyValue $Before $PropertyName) | ForEach-Object { ConvertTo-StableItem $_ }
    $afterItems = Get-Array (Get-PropertyValue $After $PropertyName) | ForEach-Object { ConvertTo-StableItem $_ }
    foreach ($item in $beforeItems) {
        if ($afterItems -notcontains $item) { return $true }
    }
    return $false
}

function Test-UnknownValue {
    param([object]$Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return [bool]$Value }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $false }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($entry in $Value.GetEnumerator()) { if (Test-UnknownValue $entry.Value) { return $true } }
        return $false
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($entry in $Value) { if (Test-UnknownValue $entry) { return $true } }
        return $false
    }
    foreach ($property in $Value.PSObject.Properties) {
        if (Test-UnknownValue $property.Value) { return $true }
    }
    return $false
}

function Test-ExactSet {
    param([object[]]$Actual, [object[]]$Expected)
    $actualStrings = @($Actual | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    $expectedStrings = @($Expected | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    if ($actualStrings.Count -ne $expectedStrings.Count) { return $false }
    if ($actualStrings.Count -eq 0) { return $true }
    return -not (Compare-Object -ReferenceObject $expectedStrings -DifferenceObject $actualStrings)
}

function Test-ApplicationPolicy {
    param([string]$Address, [object]$After, [object]$ApplicationPolicy)
    if ($null -eq $After) { return $false }
    if ((Get-PropertyValue $After 'display_name') -ne $ApplicationPolicy.display_name) { return $false }
    if ((Get-PropertyValue $After 'sign_in_audience') -ne $ApplicationPolicy.sign_in_audience) { return $false }
    if ((Get-PropertyValue $After 'fallback_public_client_enabled') -eq $true) { return $false }
    if (@(Get-Array (Get-PropertyValue $After 'owners')).Count -lt 1) { return $false }
    if (@(Get-Array (Get-PropertyValue $After 'password')).Count -gt 0 -or
        @(Get-Array (Get-PropertyValue $After 'password_credentials')).Count -gt 0 -or
        @(Get-Array (Get-PropertyValue $After 'key_credentials')).Count -gt 0) { return $false }

    $web = Get-PropertyValue $After 'web'
    if ($web -is [System.Collections.IList]) { $web = @($web) | Select-Object -First 1 }
    $actualRedirects = if ($null -eq $web) { @() } else { Get-Array (Get-PropertyValue $web 'redirect_uris') }
    if (-not (Test-ExactSet $actualRedirects (Get-Array $ApplicationPolicy.redirect_uris))) { return $false }
    $actualHomepage = if ($null -eq $web) { $null } else { Get-PropertyValue $web 'homepage_url' }
    $actualLogout = if ($null -eq $web) { $null } else { Get-PropertyValue $web 'logout_url' }
    if ($actualHomepage -ne $ApplicationPolicy.homepage_url -or $actualLogout -ne $ApplicationPolicy.logout_url) { return $false }
    if ($null -ne $web) {
        $implicitGrant = Get-PropertyValue $web 'implicit_grant'
        if ($implicitGrant -is [System.Collections.IList]) { $implicitGrant = @($implicitGrant) | Select-Object -First 1 }
        if ($null -ne $implicitGrant -and
            ((Get-PropertyValue $implicitGrant 'access_token_issuance_enabled') -eq $true -or
             (Get-PropertyValue $implicitGrant 'id_token_issuance_enabled') -eq $true)) { return $false }
    }

    $expectedRoles = @{}
    foreach ($property in $ApplicationPolicy.app_roles.PSObject.Properties) { $expectedRoles[$property.Name] = [string]$property.Value }
    $actualRoles = @(Get-Array (Get-PropertyValue $After 'app_role'))
    if ($actualRoles.Count -ne $expectedRoles.Count) { return $false }
    foreach ($role in $actualRoles) {
        $value = [string](Get-PropertyValue $role 'value')
        if (-not $expectedRoles.ContainsKey($value) -or [string](Get-PropertyValue $role 'id') -ne $expectedRoles[$value]) { return $false }
        if (-not [bool](Get-PropertyValue $role 'enabled')) { return $false }
        if (-not (Test-ExactSet (Get-Array (Get-PropertyValue $role 'allowed_member_types')) @('User'))) { return $false }
    }

    $actualAccess = @(Get-Array (Get-PropertyValue $After 'required_resource_access'))
    if (-not (Test-ExactSet ($actualAccess | ForEach-Object { ConvertTo-StableItem $_ }) (Get-Array $ApplicationPolicy.required_resource_access | ForEach-Object { ConvertTo-StableItem $_ }))) { return $false }
    return $true
}

function Test-ServicePrincipalPolicy {
    param([object]$After)
    if ($null -eq $After) { return $false }
    if (@(Get-Array (Get-PropertyValue $After 'owners')).Count -lt 1) { return $false }
    if ((Get-PropertyValue $After 'app_role_assignment_required') -ne $true) { return $false }
    foreach ($name in @('password','password_credentials','key_credentials','saml_single_sign_on')) {
        if (@(Get-Array (Get-PropertyValue $After $name)).Count -gt 0) { return $false }
    }
    return $true
}

function Get-PlanJson {
    if ($PSCmdlet.ParameterSetName -eq 'JsonFixture') {
        return [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $PlanJsonPath))
    }
    $resolvedPlan = (Resolve-Path -LiteralPath $PlanPath).Path
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'terraform'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add('show')
    $startInfo.ArgumentList.Add('-json')
    $startInfo.ArgumentList.Add($resolvedPlan)
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'show failed' }
        $json = $process.StandardOutput.ReadToEnd()
        $null = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw 'show failed' }
        return $json
    }
    finally {
        $process.Dispose()
    }
}

function Write-Classification {
    param([string]$Classification, [int]$Creates, [int]$Updates, [int]$Deletes, [string]$PolicyVersion)
    if ($GitHubOutputPath) {
        @(
            "classification=$Classification"
            "creates=$Creates"
            "updates=$Updates"
            "deletes=$Deletes"
            "policy_version=$PolicyVersion"
        ) | Add-Content -LiteralPath $GitHubOutputPath -Encoding utf8NoBOM
    }
    Write-Output "TERRAFORM_PLAN_CLASSIFIED: $Classification"
    Write-Output "TERRAFORM_ACTION_COUNTS: create=$Creates update=$Updates delete=$Deletes"
    Write-Output "TERRAFORM_POLICY_VERSION: $PolicyVersion"
}

try {
    $policy = Get-Content -Raw -LiteralPath $PolicyPath | ConvertFrom-Json -Depth 50
    if ($policy.environment -ne $Environment -or
        [string]$policy.policy_version -ne '2026-10-31.1' -or
        [string]$policy.terraform_json_format_major -ne '1') { throw 'policy mismatch' }
    $plan = Get-PlanJson | ConvertFrom-Json -Depth 100
    if ([string]$plan.format_version -notmatch '^1\.' -or
        [string]$plan.terraform_version -ne [string]$policy.terraform_version) { throw 'version mismatch' }

    $allowedResources = @{}
    foreach ($property in $policy.allowed_resources.PSObject.Properties) { $allowedResources[$property.Name] = [string]$property.Value }
    $creates = 0; $updates = 0; $deletes = 0
    foreach ($change in @(Get-Array $plan.resource_changes)) {
        $address = [string](Get-PropertyValue $change 'address')
        $type = [string](Get-PropertyValue $change 'type')
        $mode = [string](Get-PropertyValue $change 'mode')
        if ($mode -eq 'data') { continue }
        if ($mode -ne 'managed' -or -not $allowedResources.ContainsKey($address) -or $allowedResources[$address] -ne $type) { throw 'resource not allowed' }
        $changeBody = Get-PropertyValue $change 'change'
        $actions = @(Get-Array (Get-PropertyValue $changeBody 'actions'))
        $unsupportedActions = @($actions | Where-Object { $_ -notin @('no-op','read','create','update','delete') })
        if ($actions.Count -lt 1 -or $unsupportedActions.Count -gt 0) { throw 'unknown action' }
        if (Test-UnknownValue (Get-PropertyValue $changeBody 'after_unknown')) { throw 'unknown value' }
        if ($actions -contains 'delete') { $deletes++ }
        if ($actions -contains 'create') { $creates++ }
        if ($actions -contains 'update') { $updates++ }

        $before = Get-PropertyValue $changeBody 'before'
        $after = Get-PropertyValue $changeBody 'after'
        if ($actions -contains 'update') {
            foreach ($field in @('owners','app_role','required_resource_access','password','password_credentials','key_credentials','federated_identity_credential')) {
                if (Test-CollectionRemoval $before $after $field) { $deletes++ }
            }
            $beforeWeb = Get-PropertyValue $before 'web'; $afterWeb = Get-PropertyValue $after 'web'
            if ($beforeWeb -is [System.Collections.IList]) { $beforeWeb = @($beforeWeb) | Select-Object -First 1 }
            if ($afterWeb -is [System.Collections.IList]) { $afterWeb = @($afterWeb) | Select-Object -First 1 }
            if (Test-CollectionRemoval $beforeWeb $afterWeb 'redirect_uris') { $deletes++ }
        }
        if ($actions -notcontains 'delete') {
            if ($type -eq 'azuread_application') {
                $appPolicy = Get-PropertyValue $policy.applications $address
                if (-not (Test-ApplicationPolicy $address $after $appPolicy)) { throw 'application policy mismatch' }
            }
            elseif (-not (Test-ServicePrincipalPolicy $after)) { throw 'service principal policy mismatch' }
        }
    }

    $classification = if ($deletes -gt 0) { 'DESTRUCTIVE_CHANGE' }
        elseif ($creates -gt 0 -and $updates -gt 0) { 'CREATE_AND_UPDATE' }
        elseif ($creates -gt 0) { 'CREATE_ONLY' }
        elseif ($updates -gt 0) { 'UPDATE_ONLY' }
        else { 'NO_CHANGE' }
    Write-Classification $classification $creates $updates $deletes ([string]$policy.policy_version)
}
catch {
    Write-Classification 'UNKNOWN_OR_UNVERIFIABLE' 0 0 0 'unverified'
    $safeReason = switch ($_.Exception.Message) {
        'policy mismatch' { 'ENVIRONMENT_MISMATCH' }
        'version mismatch' { 'VERSION_MISMATCH' }
        'resource not allowed' { 'RESOURCE_NOT_ALLOWED' }
        'unknown action' { 'ACTION_UNKNOWN' }
        'unknown value' { 'VALUE_UNKNOWN' }
        'application policy mismatch' { 'APPLICATION_POLICY_MISMATCH' }
        'service principal policy mismatch' { 'SERVICE_PRINCIPAL_POLICY_MISMATCH' }
        default { 'INPUT_UNVERIFIABLE' }
    }
    Write-Output "TERRAFORM_PLAN_POLICY_REASON: $safeReason"
    Write-Error 'TERRAFORM_PLAN_POLICY_FAILED: FAILED' -ErrorAction Continue
    exit 1
}

