#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent),
    [switch]$InspectTenant,
    [switch]$ApproveReadOnlyTenantInspection,
    [string]$TenantId,
    [string]$ApplicationId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Status([string]$Code) { Write-Output $Code }
function Stop-Safe([string]$Code) { Write-Error $Code; exit 1 }

try {
    $policyPath = Join-Path $RepositoryRoot 'infrastructure/terraform/policy/development.json'
    $terraformPath = Join-Path $RepositoryRoot 'infrastructure/terraform/entra-applications.tf'
    $settingsPath = Join-Path $RepositoryRoot 'src/PlaceHub.Web/appsettings.json'
    foreach ($path in @($policyPath, $terraformPath, $settingsPath)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Stop-Safe 'LOCAL_CONFIGURATION_MISSING' } }

    $policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    $terraform = Get-Content -LiteralPath $terraformPath -Raw
    if ($policy.applications.'azuread_application.placehub_web'.display_name -ne 'placehub-frontend-development') { Stop-Safe 'APPLICATION_NAME_MISMATCH' }
    if ($policy.applications.'azuread_application.placehub_web'.redirect_uris.Count -ne 1 -or $policy.applications.'azuread_application.placehub_web'.redirect_uris[0] -ne 'https://localhost:8443/signin-oidc') { Stop-Safe 'REDIRECT_URI_MISMATCH' }
    if ($policy.applications.'azuread_application.placehub_web'.required_resource_access.Count -ne 0) { Stop-Safe 'UNAPPROVED_PERMISSION_DECLARATION_PRESENT' }
    if ($terraform -match 'Place\.Read|Calendars\.Read|Place\.ReadWrite|Calendars\.ReadWrite') { Stop-Safe 'UNAPPROVED_TERRAFORM_PERMISSION_PRESENT' }
    if ($settings.Microsoft365.Mode -ne 'OfflineMock') { Stop-Safe 'OFFLINE_DEFAULT_NOT_ENFORCED' }
    if ($settings.Microsoft365.AllowSyntheticData -ne $true) { Stop-Safe 'SYNTHETIC_PROFILE_NOT_EXPLICIT' }
    Write-Status 'LOCAL_READINESS_OK'
    Write-Status 'PERMISSION_DECLARATIONS_EMPTY'
    Write-Status 'OFFLINE_DEFAULT_CONFIRMED'

    if (-not $InspectTenant) { Write-Status 'TENANT_INSPECTION_NOT_REQUESTED'; exit 0 }
    if (-not $ApproveReadOnlyTenantInspection) { Stop-Safe 'TENANT_INSPECTION_APPROVAL_REQUIRED' }
    if ($TenantId -notmatch '^[0-9a-fA-F-]{36}$' -or $ApplicationId -notmatch '^[0-9a-fA-F-]{36}$') { Stop-Safe 'TENANT_TARGET_INVALID' }
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Stop-Safe 'AZURE_CLI_REQUIRED' }

    $account = az account show --only-show-errors 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $null -eq $account) { Stop-Safe 'AZURE_AUTHENTICATION_REQUIRED' }
    if ($account.tenantId -ne $TenantId) { Stop-Safe 'TENANT_TARGET_MISMATCH' }
    Write-Status 'TENANT_TARGET_CONFIRMED'

    $escapedAppId = [Uri]::EscapeDataString($ApplicationId)
    $application = az rest --only-show-errors --method GET --url "https://graph.microsoft.com/v1.0/applications?`$filter=appId%20eq%20'$escapedAppId'&`$select=appId,displayName,signInAudience,web,requiredResourceAccess" 2>$null | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { Stop-Safe 'APPLICATION_INSPECTION_FAILED' }
    if ($application.value.Count -ne 1) { Stop-Safe 'APPLICATION_NOT_UNIQUE' }
    Write-Status 'APPLICATION_REGISTRATION_FOUND'
    if ($application.value[0].requiredResourceAccess.Count -eq 0) { Write-Status 'PERMISSION_DECLARATIONS_EMPTY' } else { Write-Status 'PERMISSION_DECLARATIONS_PRESENT_REVIEW_REQUIRED' }
    Write-Status 'CONSENT_NOT_INFERRED_FROM_DECLARATION'
    Write-Status 'TENANT_READ_ONLY_INSPECTION_COMPLETE'
}
catch {
    Stop-Safe 'READINESS_INSPECTION_FAILED'
}
