#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$workflow = Get-Content -Raw (Join-Path $root '.github/workflows/terraform.yml')
$bootstrapPath = Join-Path $root 'scripts/Bootstrap-Terraform.ps1'
$bootstrap = Get-Content -Raw $bootstrapPath
$adr016 = Get-Content -Raw (Join-Path $root 'Docs/Adr/ADR-016-github-actions-terraform-delivery.md')
$adrIndex = Get-Content -Raw (Join-Path $root 'Docs/Adr/README.md')

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
Assert-Absent $workflow '\$\{\{\s*runner\.temp\s*\}\}' 'runner.temp is not valid in the job-level env expression context.'
Assert-True ($workflow -match 'TF_PLAN_PATH=\$RUNNER_TEMP/placehub\.tfplan.+\$GITHUB_ENV') 'Saved-plan path is not initialized from RUNNER_TEMP through GITHUB_ENV.'
$planPathInitialization = $workflow.IndexOf('TF_PLAN_PATH=$RUNNER_TEMP/placehub.tfplan', [StringComparison]::Ordinal)
$planStep = $workflow.IndexOf('- name: Create saved plan', [StringComparison]::Ordinal)
$applyStep = $workflow.IndexOf('- name: Apply the exact saved plan', [StringComparison]::Ordinal)
$cleanupStep = $workflow.IndexOf('- name: Remove saved plan', [StringComparison]::Ordinal)
Assert-True ($planPathInitialization -ge 0 -and $planPathInitialization -lt $planStep -and $planStep -lt $applyStep -and $applyStep -lt $cleanupStep) 'TF_PLAN_PATH must be exported before plan, apply, and cleanup steps.'
foreach ($stepName in @('Initialize ephemeral plan path','Register secondary masks and validate target binding','Remove saved plan')) {
    $escapedStepName = [regex]::Escape($stepName)
    Assert-True ($workflow -match "(?s)- name: $escapedStepName\s+.*?working-directory:\s*\$\{\{ runner\.temp \}\}") "Step '$stepName' must start outside the checkout-dependent working directory."
}
Assert-True ($workflow -match 'SAFE_SELECTED_ENVIRONMENT.*\$\{\{ inputs.target_environment \}\}' -and $workflow -match 'SAFE_EXPECTED_ENVIRONMENT.*\$\{\{ vars.TF_ENVIRONMENT \}\}') 'Selected environment is not bound to approved configuration.'
foreach ($category in @('TERRAFORM_INIT_FAILED','TERRAFORM_VALIDATE_FAILED','TERRAFORM_PLAN_FAILED','TERRAFORM_APPLY_FAILED')) { Assert-True ($workflow.Contains($category)) "Missing failure category $category." }

Assert-Absent $bootstrap '\$Arguments\s*-join|Write-(Host|Output|Verbose|Debug).*\$(Arguments|nativeOutput)|Format-List|Out-String|\.Exception\.Message|\$_\s*\|' 'Bootstrap may render commands, native output, or exceptions.'
Assert-Absent $bootstrap 'gh\s+variable\s+set\s+-f|gh\s+secret|Application\.ReadWrite|AppRoleAssignment\.ReadWrite' 'Bootstrap must not bulk upload dotenv, create secrets, or grant privileged Graph permissions.'
Assert-True ($bootstrap -match "expectedIssuer\s*=\s*'https://token.actions.githubusercontent.com'" -and $bootstrap -match "expectedAudience\s*=\s*'api://AzureADTokenExchange'") 'Expected OIDC issuer or audience validation missing.'
Assert-True ($bootstrap -match 'Test-FederatedCredentialExact.+\$expectedSubject' -and $bootstrap -match 'audiences\.Count\s+-eq\s+1') 'Exact OIDC audience/subject validation missing.'
Assert-True ($bootstrap -match '\$DryRun\s+-or\s+\[bool\]\$WhatIfPreference' -and $bootstrap -match "Write-SafeStatus 'PREVIEW_COMPLETE'") 'DryRun/WhatIf preview gate missing.'
Assert-True ($bootstrap.Contains('[switch]$ApproveWorkloadContributor') -and $bootstrap.Contains("if (-not `$ApproveWorkloadContributor) { Stop-Safe 'AUTHORIZATION_FAILED' }")) 'Contributor assignment lacks a separate explicit approval gate.'
Assert-True ($bootstrap.Contains('[switch]$ApproveOidcCredentialRepair') -and $bootstrap.Contains("if (`$credentialRequiresRepair -and -not `$ApproveOidcCredentialRepair) { Stop-Safe 'OIDC_VALIDATION_FAILED' }")) 'OIDC repair lacks a separate explicit approval gate.'
Assert-True ($bootstrap -match "Invoke-AzRestJsonMutation -Method patch.+existingCredential\.id" -and $bootstrap -notmatch "federatedIdentityCredentials.+-Method post.+credentialRequiresRepair") 'OIDC repair must patch the one discovered credential, not create a duplicate.'
$inlineFicBody = "'--body'," + '$ficBody'
Assert-True (-not $bootstrap.Contains("'--body','{") -and -not $bootstrap.Contains($inlineFicBody)) 'Inline JSON remains in an Azure REST invocation.'
Assert-True (($bootstrap | Select-String -Pattern 'Invoke-AzRestJsonMutation' -AllMatches).Matches.Count -ge 3) 'Container and federated credential JSON do not share the @file helper.'
Assert-True ($adr016 -match '\*\*Status:\*\* Accepted' -and $adr016 -match '\*\*Approval date:\*\* 2026-10-31' -and $adr016 -match '\*\*Decision authority:\*\* Project Owner approval') 'ADR-016 acceptance metadata is incomplete.'
Assert-True ($adrIndex -match '\[016\].*\| Accepted \|') 'ADR index does not mark ADR-016 Accepted.'

# Exercise the command wrapper with synthetic secret-like values. Native stdout/stderr and arguments must not escape on failure.
$functionNames = @('Stop-Safe','New-ArmResourceUrl','New-GitHubEnvironmentSubject','Test-FederatedCredentialExact','Resolve-AzureFailureCategory','Invoke-SafeCommand','Invoke-AzRestJsonMutation')
foreach ($name in $functionNames) {
    $definition = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true) | Select-Object -First 1
    Assert-True ($null -ne $definition) "Function $name not found."
    Invoke-Expression $definition.Extent.Text
}

$canary = 'ghp_SYNTHETIC_CANARY_7a81f2e0'
$syntheticGuid = '11111111-2222-3333-4444-555555555555'
$syntheticResource = '/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/rg-canary'
$syntheticContainerScope = "$syntheticResource/providers/Microsoft.Storage/storageAccounts/stcanary/blobServices/default/containers/tfstate"
$armUrl = New-ArmResourceUrl -ResourceId $syntheticContainerScope -ApiVersion '2023-05-01'
Assert-True ($armUrl -eq "https://management.azure.com${syntheticContainerScope}?api-version=2023-05-01") 'ARM container URL interpolation regressed.'
Assert-True ($bootstrap.Contains('New-ArmResourceUrl -ResourceId $containerScope')) 'Bootstrap does not use the validated ARM URL builder.'
Assert-True ($bootstrap.Contains('if (-not $storage.Succeeded)') -and $bootstrap.Contains('Invoke-AzRestJsonMutation -Method put -Url $containerApi') -and $bootstrap.Contains('if (-not $workload.Succeeded)')) 'Partial bootstrap recovery paths are missing.'
$mutableSubject = New-GitHubEnvironmentSubject -Repository 'JoergBrors/PlaceHub' -Environment 'development'
Assert-True ($mutableSubject -ceq 'repo:JoergBrors/PlaceHub:environment:development') 'Mutable GitHub environment subject is not exact.'
$immutableSubject = New-GitHubEnvironmentSubject -Repository 'JoergBrors/PlaceHub' -Environment 'development' -UseImmutableSubject -OwnerId '123456' -RepositoryId '789012'
Assert-True ($immutableSubject -ceq 'repo:JoergBrors@123456/PlaceHub@789012:environment:development') 'Immutable GitHub environment subject is not exact.'
$Repository = 'JoergBrors/PlaceHub'; $Environment = 'development'
$brokenSubject = "repo:$Repository:environment:$Environment"
Assert-True ($brokenSubject -ceq 'repo:development') 'Regression fixture no longer demonstrates PowerShell scoped-variable interpolation.'
$expectedCredential = [pscustomobject]@{issuer='https://token.actions.githubusercontent.com';subject=$mutableSubject;audiences=@('api://AzureADTokenExchange')}
$brokenCredential = [pscustomobject]@{issuer='https://token.actions.githubusercontent.com';subject=$brokenSubject;audiences=@('api://AzureADTokenExchange')}
Assert-True (Test-FederatedCredentialExact $expectedCredential $expectedCredential.issuer $mutableSubject $expectedCredential.audiences[0]) 'Exact federated credential was rejected.'
Assert-True (-not (Test-FederatedCredentialExact $brokenCredential $expectedCredential.issuer $mutableSubject $expectedCredential.audiences[0])) 'Existing repo:development credential was not detected as invalid.'
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
    catch {
        $captured = $_ | ForEach-Object { $_.ToString() }
        Assert-True ($_.Exception.Data['SafeCategory'] -eq 'AUTHENTICATION_FAILED') 'Failed subprocess lost its sanitized category.'
        Assert-True ($_.Exception.Data['NativeExitCode'] -eq 41) 'Failed subprocess native exit code was not retained internally.'
    }
    Assert-Absent $captured ([regex]::Escape($canary)) 'Synthetic token leaked through failure handling.'
    Assert-Absent $captured ([regex]::Escape($syntheticGuid)) 'Synthetic identifier leaked through failure handling.'
    Assert-True ($captured -match 'Bootstrap operation failed') 'Safe wrapper did not produce a controlled failure.'

    $argumentProbe = Join-Path $tempRoot 'argument-probe.ps1'
    Set-Content -LiteralPath $argumentProbe -Encoding utf8 -Value '@($args) | ConvertTo-Json -Compress'
    $probe = Invoke-SafeCommand 'pwsh' @('-NoProfile','-File',$argumentProbe,'rest','--method','put','--url',$armUrl,'--body','{"properties":{"publicAccess":"None"}}') 'AUTHORIZATION_FAILED' 'Json'
    Assert-True (@($probe.Data).Count -eq 7 -and @($probe.Data)[4] -eq $armUrl) 'Native Azure CLI-style arguments were split or altered.'

    $restProbe = Join-Path $tempRoot 'rest-probe.json'
    $restFake = Join-Path $tempRoot 'fake-az-rest.ps1'
    Set-Content -LiteralPath $restFake -Encoding utf8 -Value @'
$bodyIndex = [Array]::IndexOf($args, '--body')
$bodyArgument = $args[$bodyIndex + 1]
$bodyPath = $bodyArgument.Substring(1)
$bytes = [IO.File]::ReadAllBytes($bodyPath)
$record = [ordered]@{ Body=[IO.File]::ReadAllText($bodyPath); Path=$bodyPath; ExistsDuring=(Test-Path -LiteralPath $bodyPath); HasUtf8Bom=($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) }
$record | ConvertTo-Json -Compress | Set-Content -LiteralPath $env:PLACEHUB_REST_PROBE -Encoding utf8
if ($env:PLACEHUB_REST_FAIL -eq '1') { Write-Output 'HTTP 400 BadRequest RequestIsNotValidJson'; exit 40 }
exit 0
'@
    $env:PLACEHUB_REST_PROBE = $restProbe
    $env:PLACEHUB_REST_FAIL = '0'
    $containerJson = '{"properties":{"publicAccess":"None"}}'
    $null = Invoke-AzRestJsonMutation -Method put -Url $armUrl -JsonBody $containerJson -AzureCli $restFake
    $restRecord = Get-Content -Raw $restProbe | ConvertFrom-Json
    Assert-True ($restRecord.Body -ceq $containerJson -and $restRecord.ExistsDuring -and -not $restRecord.HasUtf8Bom) 'UTF-8 @file JSON changed before reaching the simulated Azure CLI.'
    Assert-True (-not (Test-Path -LiteralPath $restRecord.Path)) 'Temporary JSON body survived a successful invocation.'

    $ficJson = '{"name":"github-development","issuer":"https://token.actions.githubusercontent.com","subject":"repo:owner/repo:environment:development","audiences":["api://AzureADTokenExchange"]}'
    $null = Invoke-AzRestJsonMutation -Method post -Url 'https://graph.microsoft.com/v1.0/applications/synthetic/federatedIdentityCredentials' -JsonBody $ficJson -Headers 'Content-Type=application/json' -AzureCli $restFake
    $ficRecord = Get-Content -Raw $restProbe | ConvertFrom-Json
    Assert-True ($ficRecord.Body -ceq $ficJson -and -not (Test-Path -LiteralPath $ficRecord.Path)) 'Federated credential JSON changed or its temporary file survived.'

    $env:PLACEHUB_REST_FAIL = '1'
    try { $null = Invoke-AzRestJsonMutation -Method put -Url $armUrl -JsonBody $containerJson -AzureCli $restFake; throw 'Expected synthetic HTTP 400 failure.' }
    catch {
        Assert-True ($_.Exception.Data['SafeCategory'] -eq 'REQUEST_INVALID') 'HTTP 400 was not classified as REQUEST_INVALID.'
        Assert-True ($_.Exception.Data['NativeExitCode'] -eq 40) 'HTTP 400 native exit code was not retained.'
    }
    $failedRecord = Get-Content -Raw $restProbe | ConvertFrom-Json
    Assert-True (-not (Test-Path -LiteralPath $failedRecord.Path)) 'Temporary JSON body survived a failed invocation.'

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
    Remove-Item Env:PLACEHUB_REST_PROBE -ErrorAction SilentlyContinue
    Remove-Item Env:PLACEHUB_REST_FAIL -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

Write-Host 'Static and synthetic logging safety checks passed.'
