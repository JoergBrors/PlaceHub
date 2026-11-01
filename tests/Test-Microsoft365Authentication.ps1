$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$program = Get-Content (Join-Path $root 'src/PlaceHub.Web/Program.cs') -Raw
$authentication = Get-Content (Join-Path $root 'src/PlaceHub.Web/Microsoft365Authentication.cs') -Raw
$normalPages = @('Home.razor','Placeholder.razor','DeskPools.razor','Parking.razor','BookingCalendar.razor') | ForEach-Object { Get-Content (Join-Path $root "src/PlaceHub.Web/Components/Pages/$_") -Raw }

foreach ($required in @('AddMicrosoftIdentityWebApp','EnableTokenAcquisitionToCallDownstreamApi','UseAuthentication','UseAuthorization','ValidateIssuer = true','ValidateAudience = true','UsePkce = true','SaveTokens = false')) {
    if (-not $program.Contains($required)) { throw 'OIDC_SECURITY_CONTROL_MISSING' }
}
foreach ($required in @('TOKEN_TENANT_MISMATCH','TOKEN_SUBJECT_MISMATCH','TOKEN_AUDIENCE_INVALID','EFFECTIVE_SCOPE_MISSING','APPLICATION_ROLE_MISSING','APPLICATION_ROLE_AMBIGUOUS','LOCATION_ASSIGNMENT_MISSING')) {
    if (-not $authentication.Contains($required)) { throw 'AUTHORIZATION_FAIL_CLOSED_CONTROL_MISSING' }
}
foreach ($page in $normalPages) {
    if ($page -match 'SyntheticResources|synthetic\.invalid|new ReadAuthorizationContext\("offline"') { throw 'SYNTHETIC_NORMAL_RUNTIME_PATH_PRESENT' }
}
if ($program -notmatch 'Microsoft365ReadOnly.+MicrosoftIdentityDelegatedTokenProvider' -and $program -notmatch 'AddScoped<IDelegatedTokenProvider, MicrosoftIdentityDelegatedTokenProvider>') { throw 'REAL_DELEGATED_PROVIDER_NOT_REGISTERED' }
'MICROSOFT365_AUTHENTICATION_STATIC_OK'
