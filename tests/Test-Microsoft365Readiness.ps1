$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$script = Join-Path $root 'scripts/Test-Microsoft365Readiness.ps1'
$result = & $script -RepositoryRoot $root
foreach ($expected in @('LOCAL_READINESS_OK','PERMISSION_DECLARATIONS_EMPTY','LIVE_FIRST_DEFAULT_CONFIRMED','SYNTHETIC_TEST_PROFILE_ISOLATED','TENANT_INSPECTION_NOT_REQUESTED')) { if ($result -notcontains $expected) { throw 'READINESS_STATUS_MISSING' } }
$settings = Get-Content -LiteralPath (Join-Path $root 'src/PlaceHub.Web/appsettings.json') -Raw | ConvertFrom-Json
if ($settings.Microsoft365.AllowSyntheticData -ne $false) { throw 'SYNTHETIC_DATA_ENABLED_IN_NORMAL_RUNTIME' }
$source = Get-Content -LiteralPath $script -Raw
foreach ($forbidden in @('--method POST','--method PATCH','--method PUT','--method DELETE','admin-consent','credential reset')) { if ($source -match [regex]::Escape($forbidden)) { throw 'READINESS_SCRIPT_MUTATION_PRESENT' } }
'MICROSOFT365_READINESS_TESTS_OK'
