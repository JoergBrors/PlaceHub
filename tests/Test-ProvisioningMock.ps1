$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot '..\scripts\PlaceHub.Provisioning.Mock.psm1'
Import-Module $module -Force
$result = Invoke-PlaceHubMockProvisioning -Operation CreateDeskPoolWorkspace -LogicalResourceId workspace-berlin-nord -CorrelationId ('a' * 32) -WhatIf
if ($null -eq $result -or $result.Code -ne 'MOCK_PREVIEW') { throw 'MOCK_PREVIEW_TEST_FAILED' }
$source = Get-Content $module -Raw
foreach ($forbidden in @('Connect-ExchangeOnline','New-Mailbox','Set-Mailbox','Set-PlaceV3','Invoke-MgGraphRequest')) {
    if ($source -match [regex]::Escape($forbidden)) { throw 'LIVE_COMMAND_PRESENT' }
}
'PROVISIONING_MOCK_TESTS_OK'
