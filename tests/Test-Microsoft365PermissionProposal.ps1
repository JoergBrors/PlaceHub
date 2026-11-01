$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$script = Join-Path $root 'scripts/Test-Microsoft365PermissionProposal.ps1'
$result = & $script -RepositoryRoot $root
foreach ($expected in @('PERMISSION_PROPOSAL_VALID','ACTIVE_PERMISSION_POLICY_UNCHANGED','ADMIN_CONSENT_NOT_GRANTED')) { if ($result -notcontains $expected) { throw 'PERMISSION_PROPOSAL_STATUS_MISSING' } }
$source = Get-Content -LiteralPath $script -Raw
foreach ($forbidden in @('az ad app permission add','--method POST','--method PATCH','--method PUT','admin-consent --')) { if ($source -match [regex]::Escape($forbidden)) { throw 'PERMISSION_PROPOSAL_MUTATION_PRESENT' } }
'MICROSOFT365_PERMISSION_PROPOSAL_TESTS_OK'
