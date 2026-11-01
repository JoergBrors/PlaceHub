#requires -Version 7.0
[CmdletBinding()]
param([string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference = 'Stop'
function Stop-Safe([string]$Code) { Write-Error $Code; exit 1 }
try {
    $manifestPath = Join-Path $RepositoryRoot 'infrastructure/terraform/proposals/development-m365-permissions.json'
    $activeTerraformPath = Join-Path $RepositoryRoot 'infrastructure/terraform/entra-applications.tf'
    $activePolicyPath = Join-Path $RepositoryRoot 'infrastructure/terraform/policy/development.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $activeTerraform = Get-Content -LiteralPath $activeTerraformPath -Raw
    $activePolicy = Get-Content -LiteralPath $activePolicyPath -Raw | ConvertFrom-Json
    if ($manifest.status -ne 'DECLARATION_APPROVED_CONSENT_GATED' -or $manifest.automatic_apply_allowed -ne $false) { Stop-Safe 'PROPOSAL_ACTIVATION_INVALID' }
    $expected = @{
        'Place.Read.All'=@('cb8f45a0-5c2e-4ea1-b803-84b870a7d7ec','Scope','microsoft_graph')
        'Calendars.ReadBasic'=@('662d75ba-a364-42ad-adee-f5f880ea4878','Scope','microsoft_graph')
        'Place.ReadWrite.All'=@('f1f5e9aa-ad18-4b97-883e-6aa7e95b7a5f','Role','microsoft_graph')
        'Exchange.ManageAsApp'=@('dc50a0fb-09a3-484d-be87-e023b12c6440','Role','exchange_online')
    }
    $entries = @($manifest.applications.'placehub-frontend-development') + @($manifest.applications.'placehub-m365-provisioning-development')
    if ($entries.Count -ne $expected.Count) { Stop-Safe 'PROPOSAL_PERMISSION_COUNT_INVALID' }
    foreach ($entry in $entries) {
        $item = $expected[$entry.name]
        if ($null -eq $item -or $entry.id -ne $item[0] -or $entry.type -cne $item[1] -or $entry.resource -cne $item[2]) { Stop-Safe 'PROPOSAL_PERMISSION_MISMATCH' }
    }
    if ($manifest.resource_applications.microsoft_graph -ne '00000003-0000-0000-c000-000000000000' -or $manifest.resource_applications.exchange_online -ne '00000002-0000-0ff1-ce00-000000000000') { Stop-Safe 'PROPOSAL_RESOURCE_APPLICATION_MISMATCH' }
    if ($activeTerraform -notmatch 'Place\.Read\.All' -or $activeTerraform -notmatch 'Calendars\.ReadBasic' -or $activeTerraform -match 'Place\.ReadWrite|Calendars\.ReadWrite|Exchange\.ManageAsApp') { Stop-Safe 'ACTIVE_PERMISSION_BOUNDARY_INVALID' }
    if (@($activePolicy.applications.'azuread_application.placehub_web'.required_resource_access).Count -ne 1 -or @($activePolicy.applications.'azuread_application.m365_provisioning'.required_resource_access).Count -ne 0) { Stop-Safe 'ACTIVE_POLICY_PERMISSION_INVALID' }
    'PERMISSION_PROPOSAL_VALID'
    'ACTIVE_READ_ONLY_PERMISSION_POLICY_EXACT'
    'ADMIN_CONSENT_NOT_GRANTED'
}
catch { Stop-Safe 'PERMISSION_PROPOSAL_INVALID' }
