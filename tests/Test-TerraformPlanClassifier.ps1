#requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$classifier = Join-Path $root 'scripts/Classify-TerraformPlan.ps1'
$policy = Join-Path $root 'infrastructure/terraform/policy/development.json'
$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("placehub-classifier-" + [guid]::NewGuid().Guid)
$null = New-Item -ItemType Directory -Path $temporaryDirectory

function New-WebAfter {
    param([object[]]$Owners = @('synthetic-owner'))
    return [ordered]@{
        display_name = 'placehub-frontend-development'
        sign_in_audience = 'AzureADMyOrg'
        fallback_public_client_enabled = $false
        owners = $Owners
        app_role = @(
            @{ value='PlaceHub.OfficeManager'; id='166b3fc4-fb93-401b-b856-bffa0d682447'; enabled=$true; allowed_member_types=@('User') },
            @{ value='PlaceHub.LocationManager'; id='228e1fa0-cca2-4ac4-bc44-987ee444ba4c'; enabled=$true; allowed_member_types=@('User') },
            @{ value='PlaceHub.SystemAdministrator'; id='9a3f940c-08c4-4bd7-8cfa-106eaab349a5'; enabled=$true; allowed_member_types=@('User') }
        )
        required_resource_access = @()
        web = @{
            homepage_url='https://localhost:8443/'
            logout_url='https://localhost:8443/signout-callback-oidc'
            redirect_uris=@('https://localhost:8443/signin-oidc')
            implicit_grant=@{ access_token_issuance_enabled=$false; id_token_issuance_enabled=$false }
        }
    }
}

function New-Change {
    param([string]$Address, [string]$Type, [string[]]$Actions, [object]$Before, [object]$After, [object]$AfterUnknown = @{})
    return [ordered]@{ address=$Address; mode='managed'; type=$Type; change=[ordered]@{ actions=$Actions; before=$Before; after=$After; after_unknown=$AfterUnknown } }
}

function Invoke-Case {
    param([string]$Name, [object[]]$Changes, [string]$Expected, [int]$ExpectedExit = 0, [string]$Canary, [string]$ExpectedUnknownField)
    $path = Join-Path $temporaryDirectory "$Name.json"
    [ordered]@{ format_version='1.2'; terraform_version='1.16.1'; resource_changes=$Changes } |
        ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
    $output = & pwsh -NoProfile -File $classifier -PlanJsonPath $path -PolicyPath $policy -Environment development 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne $ExpectedExit) { throw "$Name returned exit $exitCode instead of $ExpectedExit. Classifier output: $output" }
    if ($output -notmatch [regex]::Escape("TERRAFORM_PLAN_CLASSIFIED: $Expected")) { throw "$Name did not classify as $Expected." }
    if ($Canary -and $output.Contains($Canary)) { throw "$Name exposed fixture content." }
    if ($ExpectedUnknownField -and $output -notmatch [regex]::Escape("TERRAFORM_PLAN_UNKNOWN_FIELD: $ExpectedUnknownField")) { throw "$Name did not emit the expected safe field diagnostic." }
    if ($output -match '(?m)^Write-Error:|\s+Line \|') { throw "$Name emitted a PowerShell stack trace." }
}

try {
    $web = New-WebAfter
    $sp = @{ owners=@('synthetic-owner'); app_role_assignment_required=$true }
    Invoke-Case no-change @() NO_CHANGE
    Invoke-Case create @(New-Change azuread_application.placehub_web azuread_application @('create') $null $web) CREATE_ONLY
    Invoke-Case create-with-computed-id @(New-Change azuread_application.placehub_web azuread_application @('create') $null $web @{ app_role_ids=$true; client_id=$true; feature_tags=$true; object_id=$true; tags=$true }) CREATE_ONLY
    Invoke-Case service-principal-computed-outputs @(New-Change azuread_service_principal.placehub_web azuread_service_principal @('create') $null $sp @{ app_roles=$true; application_tenant_id=$true; client_id=$true; display_name=$true; homepage_url=$true; object_id=$true; redirect_uris=$true; service_principal_names=$true; sign_in_audience=$true; tags=$true; type=$true }) CREATE_ONLY
    Invoke-Case update @(New-Change azuread_service_principal.placehub_web azuread_service_principal @('update') $sp $sp) UPDATE_ONLY
    Invoke-Case mixed @(
        New-Change azuread_application.placehub_web azuread_application @('create') $null $web
        New-Change azuread_service_principal.placehub_web azuread_service_principal @('update') $sp $sp
    ) CREATE_AND_UPDATE
    Invoke-Case delete @(New-Change azuread_application.placehub_web azuread_application @('delete') $web $null) DESTRUCTIVE_CHANGE
    Invoke-Case replace-delete-create @(New-Change azuread_application.placehub_web azuread_application @('delete','create') $web $web) DESTRUCTIVE_CHANGE
    Invoke-Case replace-create-delete @(New-Change azuread_application.placehub_web azuread_application @('create','delete') $web $web) DESTRUCTIVE_CHANGE

    $ownerCanary = 'OWNER_SECRET_CANARY_91c5'
    $beforeOwner = @{ owners=@('synthetic-owner',$ownerCanary); app_role_assignment_required=$true }
    Invoke-Case owner-removal @(New-Change azuread_service_principal.placehub_web azuread_service_principal @('update') $beforeOwner $sp) DESTRUCTIVE_CHANGE 0 $ownerCanary

    $permissionBefore = New-WebAfter
    $permissionBefore.required_resource_access = @(@{ resource_app_id='00000003-0000-0000-c000-000000000000'; resource_access=@(@{id='synthetic-sensitive-id';type='Scope'}) })
    Invoke-Case permission-removal @(New-Change azuread_application.placehub_web azuread_application @('update') $permissionBefore $web) DESTRUCTIVE_CHANGE 0 'synthetic-sensitive-id'
    Invoke-Case unknown-action @(New-Change azuread_application.placehub_web azuread_application @('future-action') $null $web) UNKNOWN_OR_UNVERIFIABLE 1
    Invoke-Case unknown-value @(New-Change azuread_application.placehub_web azuread_application @('create') $null $web @{ owners=$true }) UNKNOWN_OR_UNVERIFIABLE 1 $null owners
    Invoke-Case unapproved-resource @(New-Change azurerm_linux_web_app.forbidden azurerm_linux_web_app @('create') $null @{}) UNKNOWN_OR_UNVERIFIABLE 1

    $wrongVersionPath = Join-Path $temporaryDirectory 'wrong-version.json'
    @{ format_version='2.0'; terraform_version='1.16.1'; resource_changes=@() } | ConvertTo-Json | Set-Content -LiteralPath $wrongVersionPath
    $versionOutput = & pwsh -NoProfile -File $classifier -PlanJsonPath $wrongVersionPath -PolicyPath $policy -Environment development 2>&1 | Out-String
    if ($LASTEXITCODE -ne 1 -or $versionOutput -notmatch 'UNKNOWN_OR_UNVERIFIABLE') { throw 'Unsupported JSON format did not fail closed.' }
    Write-Output 'TERRAFORM_CLASSIFIER_TESTS_OK'
}
finally {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
}

