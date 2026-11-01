$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$script = Join-Path $root 'scripts/Test-Microsoft365Readiness.ps1'
$result = & $script -RepositoryRoot $root
foreach ($expected in @('LOCAL_READINESS_OK','PERMISSION_DECLARATIONS_EMPTY','OFFLINE_DEFAULT_CONFIRMED','TENANT_INSPECTION_NOT_REQUESTED')) { if ($result -notcontains $expected) { throw 'READINESS_STATUS_MISSING' } }
$settings = Get-Content -LiteralPath (Join-Path $root 'src/PlaceHub.Web/appsettings.json') -Raw | ConvertFrom-Json
if ($settings.Microsoft365.AllowSyntheticData -ne $true) { throw 'SYNTHETIC_PROFILE_NOT_EXPLICIT' }
$source = Get-Content -LiteralPath $script -Raw
foreach ($forbidden in @('--method POST','--method PATCH','--method PUT','--method DELETE','admin-consent','credential reset')) { if ($source -match [regex]::Escape($forbidden)) { throw 'READINESS_SCRIPT_MUTATION_PRESENT' } }
'MICROSOFT365_READINESS_TESTS_OK'
