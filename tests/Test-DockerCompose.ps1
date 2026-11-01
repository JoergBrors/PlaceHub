$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$compose = Get-Content (Join-Path $root 'compose.yaml') -Raw
$synthetic = Get-Content (Join-Path $root 'compose.synthetic-test.yaml') -Raw
$worker = Get-Content (Join-Path $root 'src/PlaceHub.Worker/Program.cs') -Raw
$dockerIgnore = Get-Content (Join-Path $root '.dockerignore') -Raw
$tlsInitializer = Get-Content (Join-Path $root 'scripts/Initialize-LocalTls.ps1') -Raw
$entraCertificateInitializer = Get-Content (Join-Path $root 'scripts/Initialize-LocalEntraCertificate.ps1') -Raw
$plan = Get-Content (Join-Path $root '.azure/infrastructure-plan.json') -Raw | ConvertFrom-Json

function Assert-Contains([string]$Text, [string]$Expected, [string]$Code) {
    if (-not $Text.Contains($Expected)) { throw $Code }
}

Assert-Contains $compose '127.0.0.1:3242:8443' 'COMPOSE_HTTPS_LOOPBACK_BINDING_MISSING'
if ($compose -match '(?m)^\s*-?\s*[^#\r\n]*3323:') { throw 'COMPOSE_DIAGNOSTICS_PORT_MUST_NOT_BE_PUBLIC'
}
Assert-Contains $compose 'Microsoft365__Mode: Microsoft365ReadOnly' 'COMPOSE_LIVE_FIRST_MODE_MISSING'
Assert-Contains $compose 'Microsoft365__AllowSyntheticData: "false"' 'COMPOSE_SYNTHETIC_DATA_NOT_DISABLED'
Assert-Contains $compose 'Microsoft365__CredentialProvider: Certificate' 'COMPOSE_ENTRA_CERTIFICATE_PROVIDER_MISSING'
Assert-Contains $compose 'Microsoft365__ClientCertificatePath: /run/placehub-tls/client-auth.pfx' 'COMPOSE_ENTRA_CERTIFICATE_PATH_MISSING'
Assert-Contains $compose 'PlaceHub__LocationAssignmentList: ${PLACEHUB_USER_OBJECT_ID:-UNASSIGNED}=${PLACEHUB_LOCATION_PLACE_ID:-UNASSIGNED}' 'COMPOSE_LOCATION_ASSIGNMENT_FAIL_CLOSED_MAPPING_MISSING'
if ($compose -match 'PlaceHub__LocationAssignments__\$\{') { throw 'COMPOSE_INTERPOLATES_VARIABLE_NAME' }
foreach ($untrustedFlag in @('Microsoft365__PermissionsApproved','Microsoft365__ConsentVerified','Microsoft365__TenantCapabilityVerified')) { if ($compose.Contains($untrustedFlag)) { throw 'COMPOSE_UNVERIFIED_LIVE_FLAG_PRESENT' } }
Assert-Contains $compose 'source: ${PLACEHUB_TLS_DIRECTORY:?PLACEHUB_TLS_DIRECTORY required}' 'COMPOSE_TLS_DIRECTORY_NOT_REQUIRED'
Assert-Contains $compose 'read_only: true' 'COMPOSE_READ_ONLY_BOUNDARY_MISSING'
Assert-Contains $compose 'Worker__Enabled: "false"' 'COMPOSE_WORKER_DEFAULT_NOT_DISABLED'
Assert-Contains $compose 'Worker__KeyVaultNetworkPathVerified: "false"' 'COMPOSE_NETWORK_GATE_MISSING'
Assert-Contains $compose 'Worker__CredentialBootstrapVerified: "false"' 'COMPOSE_CREDENTIAL_GATE_MISSING'
if ($compose.Contains('/var/run/docker.sock')) { throw 'COMPOSE_DOCKER_SOCKET_EXPOSED' }
if ($compose -match '(?ms)placehub-worker:.*?\n\s+ports:') { throw 'COMPOSE_WORKER_PORT_EXPOSED' }

Assert-Contains $synthetic 'Microsoft365__Mode: OfflineMock' 'COMPOSE_SYNTHETIC_OVERRIDE_MISSING'
Assert-Contains $synthetic 'Microsoft365__AllowSyntheticData: "true"' 'COMPOSE_SYNTHETIC_OVERRIDE_NOT_EXPLICIT'
Assert-Contains $synthetic '127.0.0.1:3243:8443' 'COMPOSE_SYNTHETIC_PORT_NOT_SEPARATE'
if ($synthetic -match '3242') { throw 'COMPOSE_SYNTHETIC_USES_LIVE_PORT' }
Assert-Contains $worker 'PRIVILEGED_EXECUTION_NOT_ACTIVATED' 'WORKER_PRIVILEGED_FAIL_CLOSED_CODE_MISSING'
Assert-Contains $dockerIgnore '**/bin/' 'DOCKERIGNORE_BIN_MISSING'
Assert-Contains $dockerIgnore '**/obj/' 'DOCKERIGNORE_OBJ_MISSING'
Assert-Contains $dockerIgnore '**/*.pfx' 'DOCKERIGNORE_PFX_MISSING'
Assert-Contains $dockerIgnore '**/*.key' 'DOCKERIGNORE_PRIVATE_KEY_MISSING'
Assert-Contains $tlsInitializer 'LOCAL_TLS_ALREADY_EXISTS' 'LOCAL_TLS_OVERWRITE_GUARD_MISSING'
Assert-Contains $tlsInitializer 'LOCAL_TLS_READY' 'LOCAL_TLS_STABLE_STATUS_MISSING'
Assert-Contains $tlsInitializer 'PLACEHUB_TLS_DIRECTORY' 'LOCAL_TLS_ENV_LOOKUP_MISSING'
if ($tlsInitializer.Contains('dev-certs https --clean')) { throw 'LOCAL_TLS_DESTRUCTIVE_CLEAN_NOT_ALLOWED' }
Assert-Contains $entraCertificateInitializer 'ENTRA_CLIENT_CERTIFICATE_ALREADY_EXISTS' 'ENTRA_CERTIFICATE_OVERWRITE_GUARD_MISSING'
Assert-Contains $entraCertificateInitializer 'ENTRA_PUBLIC_CERTIFICATE_REGISTRATION_REQUIRED' 'ENTRA_PUBLIC_CERTIFICATE_GATE_MISSING'

$keyVault = $plan.plan.resources | Where-Object type -eq 'Microsoft.KeyVault/vaults'
if (-not $keyVault) { throw 'KEY_VAULT_PLAN_MISSING' }
if ($keyVault.properties.publicNetworkAccess -ne 'Enabled') { throw 'KEY_VAULT_PUBLIC_ENDPOINT_NOT_ENABLED' }
if ($keyVault.properties.networkAclsDefaultAction -ne 'Deny') { throw 'KEY_VAULT_FIREWALL_DEFAULT_DENY_MISSING' }
if ($keyVault.properties.approvedWorkerIpv4Cidr -ne 'parameter:worker_egress_ipv4_cidr') { throw 'KEY_VAULT_WORKER_EGRESS_ALLOWLIST_MISSING' }

Write-Output if (Get-Command docker -ErrorAction SilentlyContinue) {
    # Compose resolves values only, never variable names: check the resolved configuration with synthetic identifiers.
    $env:PLACEHUB_TLS_DIRECTORY = $root; $env:PLACEHUB_USER_OBJECT_ID = '11111111-1111-1111-1111-111111111111'; $env:PLACEHUB_LOCATION_PLACE_ID = 'synthetic-building'
    try {
        $resolved = (& docker compose -f (Join-Path $root 'compose.yaml') config 2>$null) -join "`n"
        if ($LASTEXITCODE -eq 0) {
            if ($resolved -notmatch 'PlaceHub__LocationAssignmentList: 11111111-1111-1111-1111-111111111111=synthetic-building') { throw 'COMPOSE_LOCATION_ASSIGNMENT_NOT_RESOLVED' }
            if ($resolved -match '\$\{') { throw 'COMPOSE_UNRESOLVED_PLACEHOLDER' }
        }
    }
    finally { Remove-Item Env:PLACEHUB_TLS_DIRECTORY, Env:PLACEHUB_USER_OBJECT_ID, Env:PLACEHUB_LOCATION_PLACE_ID -ErrorAction SilentlyContinue }
}
'DOCKER_COMPOSE_STATIC_OK'
