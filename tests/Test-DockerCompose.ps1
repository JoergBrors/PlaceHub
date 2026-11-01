$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$compose = Get-Content (Join-Path $root 'compose.yaml') -Raw
$synthetic = Get-Content (Join-Path $root 'compose.synthetic-test.yaml') -Raw
$worker = Get-Content (Join-Path $root 'src/PlaceHub.Worker/Program.cs') -Raw
$plan = Get-Content (Join-Path $root '.azure/infrastructure-plan.json') -Raw | ConvertFrom-Json

function Assert-Contains([string]$Text, [string]$Expected, [string]$Code) {
    if (-not $Text.Contains($Expected)) { throw $Code }
}

Assert-Contains $compose '127.0.0.1:3242:8443' 'COMPOSE_HTTPS_LOOPBACK_BINDING_MISSING'
if ($compose -match '(?m)^\s*-?\s*[^#\r\n]*3323:') { throw 'COMPOSE_DIAGNOSTICS_PORT_MUST_NOT_BE_PUBLIC'
}
Assert-Contains $compose 'Microsoft365__Mode: Microsoft365ReadOnly' 'COMPOSE_LIVE_FIRST_MODE_MISSING'
Assert-Contains $compose 'Microsoft365__AllowSyntheticData: "false"' 'COMPOSE_SYNTHETIC_DATA_NOT_DISABLED'
Assert-Contains $compose 'source: ${PLACEHUB_TLS_DIRECTORY:?PLACEHUB_TLS_DIRECTORY required}' 'COMPOSE_TLS_DIRECTORY_NOT_REQUIRED'
Assert-Contains $compose 'read_only: true' 'COMPOSE_READ_ONLY_BOUNDARY_MISSING'
Assert-Contains $compose 'Worker__Enabled: "false"' 'COMPOSE_WORKER_DEFAULT_NOT_DISABLED'
Assert-Contains $compose 'Worker__KeyVaultNetworkPathVerified: "false"' 'COMPOSE_NETWORK_GATE_MISSING'
Assert-Contains $compose 'Worker__CredentialBootstrapVerified: "false"' 'COMPOSE_CREDENTIAL_GATE_MISSING'
if ($compose.Contains('/var/run/docker.sock')) { throw 'COMPOSE_DOCKER_SOCKET_EXPOSED' }
if ($compose -match '(?ms)placehub-worker:.*?\n\s+ports:') { throw 'COMPOSE_WORKER_PORT_EXPOSED' }

Assert-Contains $synthetic 'Microsoft365__Mode: OfflineMock' 'COMPOSE_SYNTHETIC_OVERRIDE_MISSING'
Assert-Contains $synthetic 'Microsoft365__AllowSyntheticData: "true"' 'COMPOSE_SYNTHETIC_OVERRIDE_NOT_EXPLICIT'
Assert-Contains $worker 'PRIVILEGED_EXECUTION_NOT_ACTIVATED' 'WORKER_PRIVILEGED_FAIL_CLOSED_CODE_MISSING'

$keyVault = $plan.plan.resources | Where-Object type -eq 'Microsoft.KeyVault/vaults'
if (-not $keyVault) { throw 'KEY_VAULT_PLAN_MISSING' }
if ($keyVault.properties.publicNetworkAccess -ne 'Enabled') { throw 'KEY_VAULT_PUBLIC_ENDPOINT_NOT_ENABLED' }
if ($keyVault.properties.networkAclsDefaultAction -ne 'Deny') { throw 'KEY_VAULT_FIREWALL_DEFAULT_DENY_MISSING' }
if ($keyVault.properties.approvedWorkerIpv4Cidr -ne 'parameter:worker_egress_ipv4_cidr') { throw 'KEY_VAULT_WORKER_EGRESS_ALLOWLIST_MISSING' }

Write-Output 'DOCKER_COMPOSE_STATIC_OK'
