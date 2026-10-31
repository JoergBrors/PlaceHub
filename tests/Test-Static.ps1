#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$workflow = Get-Content -Raw (Join-Path $root '.github/workflows/terraform.yml')
$bootstrapPath = Join-Path $root 'scripts/Bootstrap-Terraform.ps1'
$bootstrap = Get-Content -Raw $bootstrapPath

$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($bootstrapPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'PowerShell syntax validation failed.' }

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Absent([string]$Content, [string]$Pattern, [string]$Message) { if ($Content -match $Pattern) { throw $Message } }

Assert-Absent $workflow '(?m)^\s*(push|pull_request|pull_request_target|schedule):' 'Workflow must remain manual-only.'
Assert-True ($workflow -match '(?m)^\s*workflow_dispatch:') 'workflow_dispatch trigger missing.'
Assert-True ($workflow -match 'id-token:\s*write' -and $workflow -match 'contents:\s*read') 'Minimal OIDC permissions missing.'
Assert-Absent $workflow '(?i)terraform\s+destroy|upload-artifact|download-artifact|ARM_CLIENT_SECRET|AZURE_CREDENTIALS' 'Forbidden destroy, artifact, or long-lived credential pattern found.'
Assert-Absent $workflow '(?im)terraform\s+show|terraform\s+(output|state\s+(pull|show))|^\s*(printenv|env)(\s|$)|set\s+-x|TF_LOG' 'Workflow may disclose Terraform or environment data.'
Assert-True ($workflow -match 'terraform apply[^\r\n]*\$TF_PLAN_PATH') 'Apply must consume the exact saved plan.'
Assert-True ($workflow -match 'terraform plan[^\r\n]*-detailed-exitcode') 'Plan must derive only a minimal change status.'
Assert-True ($workflow -match 'Changes detected: yes' -and $workflow -match 'Changes detected: no') 'Allowlisted plan summary missing.'
Assert-True ($workflow -match 'rm -f -- "\$TF_PLAN_PATH"' -and $workflow -match '\$\{\{ always\(\) \}\}') 'Saved plan cleanup missing.'
Assert-True ($workflow -match 'SAFE_SELECTED_ENVIRONMENT.*\$\{\{ inputs.target_environment \}\}' -and $workflow -match 'SAFE_EXPECTED_ENVIRONMENT.*\$\{\{ vars.TF_ENVIRONMENT \}\}') 'Selected environment is not bound to approved configuration.'
foreach ($category in @('TERRAFORM_INIT_FAILED','TERRAFORM_VALIDATE_FAILED','TERRAFORM_PLAN_FAILED','TERRAFORM_APPLY_FAILED')) { Assert-True ($workflow.Contains($category)) "Missing failure category $category." }

Assert-Absent $bootstrap '\$Arguments\s*-join|Write-(Host|Output|Verbose|Debug).*\$(Arguments|nativeOutput)|Format-List|Out-String|\.Exception\.Message|\$_\s*\|' 'Bootstrap may render commands, native output, or exceptions.'
Assert-Absent $bootstrap 'gh\s+variable\s+set\s+-f|gh\s+secret|Application\.ReadWrite|AppRoleAssignment\.ReadWrite' 'Bootstrap must not bulk upload dotenv, create secrets, or grant privileged Graph permissions.'
Assert-True ($bootstrap -match "expectedIssuer\s*=\s*'https://token.actions.githubusercontent.com'" -and $bootstrap -match "expectedAudience\s*=\s*'api://AzureADTokenExchange'") 'Expected OIDC issuer or audience validation missing.'
Assert-True ($bootstrap -match 'audiences\.Count\s+-ne\s+1' -and $bootstrap -match 'subject\s+-cne\s+\$expectedSubject') 'Exact OIDC audience/subject validation missing.'
Assert-True ($bootstrap -match '\$DryRun\s+-or\s+\[bool\]\$WhatIfPreference' -and $bootstrap -match "Write-SafeStatus 'PREVIEW_COMPLETE'") 'DryRun/WhatIf preview gate missing.'

# Exercise the command wrapper with synthetic secret-like values. Native stdout/stderr and arguments must not escape on failure.
$functionNames = @('Stop-Safe','Invoke-SafeCommand')
foreach ($name in $functionNames) {
    $definition = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true) | Select-Object -First 1
    Assert-True ($null -ne $definition) "Function $name not found."
    Invoke-Expression $definition.Extent.Text
}

$canary = 'ghp_SYNTHETIC_CANARY_7a81f2e0'
$syntheticGuid = '11111111-2222-3333-4444-555555555555'
$syntheticResource = '/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-canary'
$bootstrapFailure = & pwsh -NoProfile -File $bootstrapPath -EnvFile '__missing__.env' -TenantId $syntheticGuid -SubscriptionId $syntheticGuid -Repository 'owner/repo' -Environment 'test' -Location 'westeurope' -StateResourceGroup 'rg-test' -StateStorageAccount $canary -StateContainer 'tfstate' -StateKey 'test.tfstate' -DeploymentAppName 'test' -ConfirmTarget $canary 2>&1
$bootstrapFailureText = $bootstrapFailure -join "`n"
Assert-Absent $bootstrapFailureText ([regex]::Escape($canary)) 'Synthetic value leaked through top-level bootstrap failure handling.'
Assert-Absent $bootstrapFailureText ([regex]::Escape($syntheticGuid)) 'Synthetic GUID leaked through top-level bootstrap failure handling.'
Assert-True ($bootstrapFailureText -eq 'CONFIGURATION_INVALID: FAILED') 'Top-level bootstrap failure was not stable and categorized.'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("placehub-safe-test-" + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $tempRoot
try {
    $fake = Join-Path $tempRoot 'fake-command.ps1'
    Set-Content -LiteralPath $fake -Encoding utf8 -Value "[Console]::Out.WriteLine(`$args[0]); [Console]::Error.WriteLine(`$args[1]); exit 41"
    $captured = ''
    try { $null = Invoke-SafeCommand 'pwsh' @('-NoProfile','-File',$fake,$canary,$syntheticResource) 'AUTHENTICATION_FAILED' }
    catch { $captured = $_ | ForEach-Object { $_.ToString() } }
    Assert-Absent $captured ([regex]::Escape($canary)) 'Synthetic token leaked through failure handling.'
    Assert-Absent $captured ([regex]::Escape($syntheticGuid)) 'Synthetic identifier leaked through failure handling.'
    Assert-True ($captured -match 'Bootstrap operation failed') 'Safe wrapper did not produce a controlled failure.'

    $marker = Join-Path $tempRoot 'mutation-ran'
    $DryRun = $true
    $result = Invoke-SafeCommand 'pwsh' @('-NoProfile','-Command',"Set-Content -LiteralPath '$marker' -Value ran") 'AUTHORIZATION_FAILED' -Mutating
    Assert-True (-not $result.Executed -and -not (Test-Path -LiteralPath $marker)) 'DryRun executed a mutation.'
    $DryRun = $false; $WhatIfPreference = $true
    $result = Invoke-SafeCommand 'pwsh' @('-NoProfile','-Command',"Set-Content -LiteralPath '$marker' -Value ran") 'AUTHORIZATION_FAILED' -Mutating
    Assert-True (-not $result.Executed -and -not (Test-Path -LiteralPath $marker)) 'WhatIf executed a mutation.'
    $WhatIfPreference = $false
}
finally {
    $WhatIfPreference = $false
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

Write-Host 'Static and synthetic logging safety checks passed.'
