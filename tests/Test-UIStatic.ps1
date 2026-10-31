$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$app = Get-Content (Join-Path $root 'src/PlaceHub.Web/Components/App.razor') -Raw
$css = Get-Content (Join-Path $root 'src/PlaceHub.Web/wwwroot/app.css') -Raw
$nav = Get-Content (Join-Path $root 'src/PlaceHub.Web/Components/Layout/NavMenu.razor') -Raw
$calendar = Get-Content (Join-Path $root 'src/PlaceHub.Web/Components/Pages/BookingCalendar.razor') -Raw
if ($app -notmatch '@Assets\["app\.css"\]') { throw 'UI_ASSET_FINGERPRINTING_MISSING' }
foreach ($token in @('--navy-900','--indigo-600','--success','--warning','--danger',':focus-visible','prefers-reduced-motion','max-width:820px')) { if ($css -notmatch [regex]::Escape($token)) { throw "UI_TOKEN_MISSING" } }
foreach ($route in @('buchungskalender','schreibtischgruppen','parkplaetze','freigaben','diagnose')) { if ($nav -notmatch $route) { throw 'UI_ROUTE_MISSING' } }
foreach ($state in @('Verfügbar','Reserviert','Unbekannt')) { if ($calendar -notmatch $state) { throw 'CALENDAR_STATE_MISSING' } }
'UI_STATIC_TESTS_OK'
