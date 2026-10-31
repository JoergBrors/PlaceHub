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
$identityArchitecture = Get-Content -Raw (Join-Path $root 'Docs/entra-application-permission-architecture.md')
$exchangeArchitecture = Get-Content -Raw (Join-Path $root 'Docs/exchange-provisioning-architecture.md')
$certificateRunbook = Get-Content -Raw (Join-Path $root 'Docs/exchange-certificate-lifecycle-runbook.md')
$localPocArchitecture = Get-Content -Raw (Join-Path $root 'Docs/local-first-poc-architecture.md')
$adrAudit = Get-Content -Raw (Join-Path $root 'Docs/adr-consistency-audit.md')
$classifierPath = Join-Path $root 'scripts/Classify-TerraformPlan.ps1'
$classifier = Get-Content -Raw $classifierPath
$entraTerraform = Get-Content -Raw (Join-Path $root 'infrastructure/terraform/entra-applications.tf')
$developmentPolicy = Get-Content -Raw (Join-Path $root 'infrastructure/terraform/policy/development.json')

$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($bootstrapPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'PowerShell syntax validation failed.' }
$classifierTokens = $null; $classifierErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($classifierPath, [ref]$classifierTokens, [ref]$classifierErrors)
if ($classifierErrors.Count) { throw 'Terraform classifier PowerShell syntax validation failed.' }

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Absent([string]$Content, [string]$Pattern, [string]$Message) { if ($Content -match $Pattern) { throw $Message } }

Assert-Absent $workflow '(?m)^\s*(push|pull_request|pull_request_target|schedule):' 'Workflow must remain manual-only.'
Assert-True ($workflow -match '(?m)^\s*workflow_dispatch:') 'workflow_dispatch trigger missing.'
Assert-True ($workflow -match 'id-token:\s*write' -and $workflow -match 'contents:\s*read') 'Minimal OIDC permissions missing.'
Assert-Absent $workflow '(?i)terraform\s+destroy|upload-artifact|download-artifact|ARM_CLIENT_SECRET|AZURE_CREDENTIALS' 'Forbidden destroy, artifact, or long-lived credential pattern found.'
Assert-Absent $workflow '(?im)terraform\s+show|terraform\s+(output|state\s+(pull|show))|^\s*(printenv|env)(\s|$)|set\s+-x|TF_LOG' 'Workflow may disclose Terraform or environment data.'
Assert-True ($workflow -match 'terraform apply[^\r\n]*\$TF_PLAN_PATH') 'Apply must consume the exact saved plan.'
Assert-True ($workflow -match 'Classify-TerraformPlan\.ps1' -and $workflow -match 'steps\.classify\.outputs\.classification') 'Structured Terraform classification is not wired into the workflow.'
Assert-True ($workflow -match 'sha256sum.+TF_PLAN_PATH' -and $workflow -match 'TERRAFORM_PLAN_INTEGRITY_FAILED') 'Exact-plan digest verification is missing.'
Assert-True ($workflow -match 'TERRAFORM_DESTRUCTIVE_APPROVAL_REQUIRED' -and $workflow -match 'UNKNOWN_OR_UNVERIFIABLE') 'Destructive or unknown plans are not fail-closed.'
Assert-True ($workflow -match 'terraform plan[^\r\n]*-detailed-exitcode') 'Plan must derive only a minimal change status.'
Assert-True ($workflow -match 'Changes detected: yes' -and $workflow -match 'Changes detected: no') 'Allowlisted plan summary missing.'
Assert-True ($workflow -match 'rm -f -- "\$TF_PLAN_PATH"' -and $workflow -match '\$\{\{ always\(\) \}\}') 'Saved plan cleanup missing.'
Assert-Absent $workflow '(?m)^\s+TF_PLAN_PATH:\s*\$\{\{\s*runner\.temp\s*\}\}' 'runner.temp is not valid in the job-level env expression context.'
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
foreach ($maskedName in @('AZURE_CLIENT_ID','AZURE_TENANT_ID','AZURE_SUBSCRIPTION_ID','TF_STATE_RG','TF_STATE_STORAGE','TF_STATE_CONTAINER','TF_STATE_KEY')) {
    Assert-True ($workflow -match "secrets\.$maskedName") "Workflow does not source $maskedName from an automatically masked Environment secret."
    Assert-Absent $workflow "vars\.$maskedName" "Workflow still exposes $maskedName through an unmasked GitHub variable."
}
Assert-Absent $workflow '(?m)^\s{6}(ARM_CLIENT_ID|ARM_TENANT_ID|ARM_SUBSCRIPTION_ID|TF_VAR_tenant_id|TF_VAR_subscription_id):' 'Sensitive identifiers must not exist in job-level env before masks are active.'
foreach ($category in @('TERRAFORM_INIT_FAILED','TERRAFORM_VALIDATE_FAILED','TERRAFORM_PLAN_FAILED','TERRAFORM_APPLY_FAILED')) { Assert-True ($workflow.Contains($category)) "Missing failure category $category." }

Assert-Absent $bootstrap '\$Arguments\s*-join|Write-(Host|Output|Verbose|Debug).*\$(Arguments|nativeOutput)|Format-List|Out-String|\.Exception\.Message|\$_\s*\|' 'Bootstrap may render commands, native output, or exceptions.'
Assert-Absent $bootstrap 'gh\s+variable\s+set\s+-f|gh\s+secret|Application\.ReadWrite|AppRoleAssignment\.ReadWrite' 'Bootstrap must not bulk upload dotenv, create secrets, or grant privileged Graph permissions.'
Assert-True ($bootstrap -match "expectedIssuer\s*=\s*'https://token.actions.githubusercontent.com'" -and $bootstrap -match "expectedAudience\s*=\s*'api://AzureADTokenExchange'") 'Expected OIDC issuer or audience validation missing.'
Assert-True ($bootstrap -match 'Test-FederatedCredentialExact.+\$expectedSubject' -and $bootstrap -match 'audiences\.Count\s+-eq\s+1') 'Exact OIDC audience/subject validation missing.'
Assert-True ($bootstrap -match '\$DryRun\s+-or\s+\[bool\]\$WhatIfPreference' -and $bootstrap -match "Write-SafeStatus 'PREVIEW_COMPLETE'") 'DryRun/WhatIf preview gate missing.'
Assert-True ($bootstrap.Contains('[switch]$ApproveWorkloadContributor') -and $bootstrap.Contains("if (-not `$ApproveWorkloadContributor) { Stop-Safe 'AUTHORIZATION_FAILED' }")) 'Contributor assignment lacks a separate explicit approval gate.'
Assert-True ($bootstrap.Contains('[switch]$ApproveOidcCredentialRepair') -and $bootstrap.Contains("if (`$credentialRequiresRepair -and -not `$ApproveOidcCredentialRepair) { Stop-Safe 'OIDC_VALIDATION_FAILED' }")) 'OIDC repair lacks a separate explicit approval gate.'
Assert-True ($bootstrap.Contains('[switch]$ApproveApplicationReadWriteOwnedByDeclaration') -and $bootstrap.Contains("if (-not `$graphPermissionDeclared -and -not `$ApproveApplicationReadWriteOwnedByDeclaration) { Stop-Safe 'AUTHORIZATION_FAILED' }")) 'Graph permission declaration lacks a separate explicit approval gate.'
Assert-True ($bootstrap.Contains("`$microsoftGraphAppId = '00000003-0000-0000-c000-000000000000'") -and $bootstrap.Contains("`$applicationReadWriteOwnedById = '18a4783c-866b-4cc7-a460-3d5e5662c884'")) 'Application.ReadWrite.OwnedBy immutable identifiers are missing.'
Assert-True ($bootstrap -match "permission','add'.+applicationReadWriteOwnedById=Role" -and $bootstrap -match 'Test-ApplicationPermissionDeclaration \$verifiedApp') 'Graph permission declaration is not added and read back exactly.'
Assert-Absent $bootstrap '(?i)permission.+admin-consent|1bfefb4e-e0b5-418b-a88f-73c46d2cc8e9|06b708a9-e830-4db3-a914-8e69da51d44f' 'Bootstrap must not grant admin consent or declare broad Graph permissions.'
Assert-True ($bootstrap -match "Invoke-AzRestJsonMutation -Method patch.+existingCredential\.id" -and $bootstrap -notmatch "federatedIdentityCredentials.+-Method post.+credentialRequiresRepair") 'OIDC repair must patch the one discovered credential, not create a duplicate.'
$inlineFicBody = "'--body'," + '$ficBody'
Assert-True (-not $bootstrap.Contains("'--body','{") -and -not $bootstrap.Contains($inlineFicBody)) 'Inline JSON remains in an Azure REST invocation.'
Assert-True (($bootstrap | Select-String -Pattern 'Invoke-AzRestJsonMutation' -AllMatches).Matches.Count -ge 3) 'Container and federated credential JSON do not share the @file helper.'
Assert-True ($adr016 -match '\*\*Status:\*\* Accepted, amended' -and $adr016 -match '\*\*Original decision date:\*\* 2026-10-31' -and $adr016 -match '\*\*Amendment date:\*\* 2026-10-31' -and $adr016 -match '\*\*Amendment authority:\*\* Project Owner approval') 'ADR-016 amendment metadata is incomplete.'
Assert-True ($adrIndex -match '\[016\].*\| Accepted \(amended\) \|') 'ADR index does not mark ADR-016 Accepted (amended).'
foreach ($adrNumber in @('001','002','003','009','010','012','013','014')) {
    $adr = Get-Content -Raw (Join-Path $root "Docs/Adr/ADR-$adrNumber-*.md")
    Assert-True ($adr -match '\*\*Status:\*\* Accepted' -and $adr -match '\*\*Approval date:\*\* 2026-10-31' -and $adr -match '\*\*Decision authority:\*\* Project Owner approval') "ADR-$adrNumber acceptance metadata is inconsistent."
    Assert-True ($adrIndex -match "\[$adrNumber\].*\| Accepted \|") "ADR index does not mark ADR-$adrNumber Accepted."
}
foreach ($adrNumber in @('004','005','006','007','008','011','015')) {
    $adr = Get-Content -Raw (Join-Path $root "Docs/Adr/ADR-$adrNumber-*.md")
    Assert-True ($adr -match '\*\*Status:\*\* Proposed') "ADR-$adrNumber was accepted despite an unresolved material decision."
    Assert-True ($adrIndex -match "\[$adrNumber\].*\| Proposed \|") "ADR index does not mark ADR-$adrNumber Proposed."
}
Assert-True ($identityArchitecture -match 'Do not create `placehub-backend-development`' -and $identityArchitecture -match 'Terraform deployment application remains unchanged') 'Identity separation decision is incomplete.'
foreach ($permissionId in @(
    'e1fe6dd8-ba31-4d61-89e7-88639da4683d',
    'cb8f45a0-5c2e-4ea1-b803-84b870a7d7ec',
    '4c06a06a-098a-4063-868e-5dfee3827264',
    '662d75ba-a364-42ad-adee-f5f880ea4878',
    '1ec239c2-d7c9-4623-a91a-a9775856bb36',
    '913b9306-0ce1-42b8-9137-6a7df690a760',
    'f1f5e9aa-ad18-4b97-883e-6aa7e95b7a5f',
    '8ba4a692-bc31-4128-9094-475872af8a53',
    'ef54d2bf-783f-4e0f-bca1-3210c0444d99',
    'dc50a0fb-09a3-484d-be87-e023b12c6440'
)) {
    Assert-True ($identityArchitecture.Contains($permissionId)) "Permission inventory is missing immutable ID $permissionId."
}
Assert-True ($identityArchitecture.Contains('Do not create a client secret.')) 'Identity architecture does not explicitly forbid client-secret fallback.'
foreach ($requiredExchangeControl in @(
    'CNG certificates are unsupported',
    'AT_KEYEXCHANGE',
    'Connect-ExchangeOnline -AppId',
    'Disconnect-ExchangeOnline -Confirm:$false',
    'dc50a0fb-09a3-484d-be87-e023b12c6440',
    'Key Vault Secrets User',
    'A resource scope cannot reliably restrict a mailbox that does not exist',
    'hardened local Windows process is the first proof target',
    'EWS and EWS Managed API are prohibited'
)) {
    Assert-True ($exchangeArchitecture.Contains($requiredExchangeControl)) "Exchange architecture is missing control: $requiredExchangeControl"
}
Assert-True ($exchangeArchitecture -match 'New-Mailbox -Equipment' -and $exchangeArchitecture -match 'Get-EXOMailbox' -and $exchangeArchitecture -match 'Set-CalendarProcessing') 'Exchange command inventory is incomplete.'
Assert-Absent $exchangeArchitecture '(?i)(create|use|fallback to).{0,30}client secret' 'Exchange architecture permits a client-secret fallback.'
Assert-True ($certificateRunbook -match '60, 30, 14 and 7 days' -and $certificateRunbook -match 'old authentication fails' -and $certificateRunbook -match 'emergency replacement') 'Certificate rotation and emergency lifecycle controls are incomplete.'
Assert-True ($certificateRunbook -match 'local certificate-store key may remain non-exportable|private key non-exportable' -and $certificateRunbook -match 'future Azure path') 'Local and future certificate paths are not clearly separated.'
foreach ($guardrail in @('zero incremental Azure cost','Microsoft 365 operations are mocked by default','does not use an Azure free tier','any Terraform `resource`','Exchange worker stays outside Compose')) {
    Assert-True ($localPocArchitecture -match [regex]::Escape($guardrail)) "Local-first architecture is missing guardrail: $guardrail"
}
Assert-True ($adrAudit -match 'ADR-by-ADR compliance matrix' -and $adrAudit -match '\| 016 Terraform delivery \| Accepted → \*\*Accepted, subsequently amended\*\*') 'ADR consistency audit is incomplete.'
$terraformGovernance = Get-Content -Raw (Join-Path $root 'Docs/terraform-change-governance.md')
foreach ($classification in @('NO_CHANGE','CREATE_ONLY','UPDATE_ONLY','CREATE_AND_UPDATE','DESTRUCTIVE_CHANGE','UNKNOWN_OR_UNVERIFIABLE')) {
    Assert-True ($adr016.Contains($classification) -and $terraformGovernance.Contains($classification)) "Terraform governance is missing classification $classification."
}
Assert-True ($adr016 -match 'Any action list containing `delete`' -and $adr016 -match 'destructive plans \*\*must fail closed\*\*') 'ADR-016 does not fail closed for delete or unavailable plan retention.'
Assert-True ($adr016 -match 'Development provisioning authorization record' -and $adr016 -match 'policy version `2026-10-31\.1`') 'ADR-016 development authorization record is incomplete.'
Assert-True ($terraformGovernance -match 'verified non-destructive path' -and $terraformGovernance -match 'DESTRUCTIVE_CHANGE.+exits before apply') 'Implemented non-destructive transition is not documented.'
Assert-True ($terraformGovernance -match 'Application.ReadWrite.OwnedBy' -and $terraformGovernance -match '`AppRoleAssignment.ReadWrite.All` is not approved') 'Entra least-privilege boundary is incomplete.'

foreach ($classification in @('NO_CHANGE','CREATE_ONLY','UPDATE_ONLY','CREATE_AND_UPDATE','DESTRUCTIVE_CHANGE','UNKNOWN_OR_UNVERIFIABLE')) {
    Assert-True ($classifier.Contains($classification)) "Classifier is missing $classification."
}
Assert-True ($classifier -match "terraform_version.+policy\.terraform_version" -and $classifier -match 'format_version') 'Classifier does not pin structured-plan compatibility.'
Assert-Absent $classifier '(?i)Write-(Host|Output|Error).*(PlanJson|PlanPath|before|after|exception\.message)' 'Classifier may print sensitive plan content.'
Assert-True ($developmentPolicy -match '"policy_version": "2026-10-31\.1"' -and $developmentPolicy -match 'https://localhost:8443/signin-oidc') 'Development policy version or exact redirect URI is missing.'
foreach ($resourceAddress in @('azuread_application.placehub_web','azuread_service_principal.placehub_web','azuread_application.m365_provisioning','azuread_service_principal.m365_provisioning')) {
    Assert-True ($developmentPolicy.Contains($resourceAddress)) "Development allowlist is missing $resourceAddress."
}
Assert-True (($entraTerraform | Select-String -Pattern '(?m)^resource "azuread_(application|service_principal)"' -AllMatches).Matches.Count -eq 4) 'Unexpected Entra Terraform resource count.'
Assert-Absent $entraTerraform '(?i)azuread_(app_role_assignment|application_password|service_principal_password|application_certificate)|required_resource_access|Exchange\.ManageAsApp|Application\.ReadWrite' 'Terraform must not grant consent, permissions, credentials or role assignments.'
Assert-Absent $entraTerraform '(?m)^resource "azurerm_' 'Paid Azure application resources are forbidden.'

# Exercise the command wrapper with synthetic secret-like values. Native stdout/stderr and arguments must not escape on failure.
$functionNames = @('Stop-Safe','New-ArmResourceUrl','New-GitHubEnvironmentSubject','Test-FederatedCredentialExact','Test-ApplicationPermissionDeclaration','Resolve-AzureFailureCategory','Invoke-SafeCommand','Invoke-AzRestJsonMutation')
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
$ownedByDeclaration = [pscustomobject]@{requiredResourceAccess=@([pscustomobject]@{resourceAppId='00000003-0000-0000-c000-000000000000';resourceAccess=@([pscustomobject]@{id='18a4783c-866b-4cc7-a460-3d5e5662c884';type='Role'})})}
$wrongDeclaration = [pscustomobject]@{requiredResourceAccess=@([pscustomobject]@{resourceAppId='00000003-0000-0000-c000-000000000000';resourceAccess=@([pscustomobject]@{id='18a4783c-866b-4cc7-a460-3d5e5662c884';type='Scope'})})}
Assert-True (Test-ApplicationPermissionDeclaration $ownedByDeclaration '00000003-0000-0000-c000-000000000000' '18a4783c-866b-4cc7-a460-3d5e5662c884') 'Exact Application.ReadWrite.OwnedBy application declaration was rejected.'
Assert-True (-not (Test-ApplicationPermissionDeclaration $wrongDeclaration '00000003-0000-0000-c000-000000000000' '18a4783c-866b-4cc7-a460-3d5e5662c884')) 'Delegated/wrong-type permission declaration was accepted.'
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
