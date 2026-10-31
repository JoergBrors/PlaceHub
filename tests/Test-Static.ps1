#requires -Version 7.2
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$workflow = Get-Content -Raw (Join-Path $root '.github/workflows/terraform.yml')
$bootstrap = Get-Content -Raw (Join-Path $root 'scripts/Bootstrap-Terraform.ps1')

$tokens = $null; $errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/Bootstrap-Terraform.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }

if ($workflow -match '(?m)^\s*(push|pull_request|schedule):') { throw 'Workflow must remain manual-only.' }
if ($workflow -notmatch '(?m)^\s*workflow_dispatch:') { throw 'workflow_dispatch trigger missing.' }
if ($workflow -notmatch 'id-token:\s*write' -or $workflow -notmatch 'contents:\s*read') { throw 'Minimal OIDC permissions missing.' }
if ($workflow -match '(?i)terraform\s+destroy|upload-artifact|ARM_CLIENT_SECRET|AZURE_CREDENTIALS') { throw 'Forbidden destroy/artifact/long-lived credential pattern found.' }
if ($workflow -notmatch 'terraform apply[^\r\n]*tfplan') { throw 'Apply must consume the saved plan.' }
if ($bootstrap -match 'gh\s+variable\s+set\s+-f|gh\s+secret') { throw 'Bootstrap must not bulk upload dotenv or create secrets.' }

Write-Host 'Static safety checks passed.'

