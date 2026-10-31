#requires -Version 7.2
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$scriptPath = Join-Path $root 'scripts/Initialize-GitHubEnvironment.ps1'

function Assert-True([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-NotContains([string]$Text, [string]$Value, [string]$Message) { if ($Text.Contains($Value)) { throw $Message } }

$tokens=$null; $parseErrors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'GitHub Environment script has PowerShell syntax errors.'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("placehub-ghenv-test-" + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $tempRoot
$fakeGh = Join-Path $tempRoot 'fake-gh.ps1'
$mutationLog = Join-Path $tempRoot 'mutations.log'

$fakeSource = @'
$scenario = $env:PLACEHUB_GH_SCENARIO
if ($args[0] -eq 'auth') {
    if ($scenario -eq 'auth-missing') { Write-Error 'ghp_SYNTHETIC_AUTH_CANARY' -ErrorAction Continue; exit 1 }
    exit 0
}
if ($args[0] -ne 'api') { exit 2 }
$endpoint = $args[1]
$method = 'GET'
$methodIndex = [Array]::IndexOf($args, '--method')
if ($methodIndex -ge 0) { $method = $args[$methodIndex + 1] }
$body = ($input | Out-String).Trim()
if ($method -ne 'GET') {
    Add-Content -LiteralPath $env:PLACEHUB_GH_MUTATION_LOG -Value "$method|$endpoint|$body"
    Write-Output '{}'
    exit 0
}
if ($endpoint -eq 'repos/JoergBrors/PlaceHub') {
    $admin = $scenario -ne 'no-admin'
    $visibility = if ($scenario -in @('unsupported','private-free')) { 'private' } else { 'public' }
    [pscustomobject]@{ permissions=@{admin=$admin}; visibility=$visibility; owner=@{login='JoergBrors';type='User'} } | ConvertTo-Json -Compress
    exit 0
}
if ($endpoint -eq 'users/JoergBrors') { $plan=if($scenario -eq 'private-free'){'free'}else{'pro'}; [pscustomobject]@{plan=@{name=$plan}} | ConvertTo-Json -Compress; exit 0 }
if ($endpoint -eq 'users/reviewer-one') { Write-Output '{"id":101,"login":"reviewer-one"}'; exit 0 }
if ($endpoint -eq 'repos/JoergBrors/PlaceHub/collaborators/reviewer-one/permission') { Write-Output '{"permission":"read"}'; exit 0 }
if ($endpoint -match '/deployment-branch-policies\?') {
    if ($scenario -eq 'existing-wrong') { Write-Output '{"branch_policies":[{"id":77,"name":"release/*","type":"branch"}]}' }
    elseif ($scenario -in @('missing','reviewers','whatif')) { Write-Output '{"branch_policies":[]}' }
    else { Write-Output '{"branch_policies":[{"id":10,"name":"main","type":"branch"}]}' }
    exit 0
}
if ($endpoint -eq 'repos/JoergBrors/PlaceHub/environments/development') {
    if ($scenario -in @('missing','reviewers','unsupported','private-free','whatif')) { Write-Error 'HTTP 404 synthetic-resource-canary' -ErrorAction Continue; exit 1 }
    $custom = $scenario -ne 'existing-protected'
    $protected = $scenario -eq 'existing-protected'
    [pscustomobject]@{ protection_rules=@(@{type='wait_timer';wait_timer=5}); deployment_branch_policy=@{protected_branches=$protected;custom_branch_policies=$custom} } | ConvertTo-Json -Depth 6 -Compress
    exit 0
}
Write-Error 'HTTP 404 unknown' -ErrorAction Continue; exit 1
'@
Set-Content -LiteralPath $fakeGh -Value $fakeSource -Encoding utf8

function Invoke-Scenario {
    param([string]$Scenario, [string[]]$ExtraArguments=@())
    Remove-Item -LiteralPath $mutationLog -Force -ErrorAction SilentlyContinue
    $env:PLACEHUB_GH_SCENARIO = $Scenario
    $env:PLACEHUB_GH_MUTATION_LOG = $mutationLog
    $output = & pwsh -NoProfile -File $scriptPath -GitHubCli $fakeGh @ExtraArguments 2>&1
    [pscustomobject]@{ ExitCode=$LASTEXITCODE; Output=($output -join "`n"); Mutations=if(Test-Path $mutationLog){Get-Content -Raw $mutationLog}else{''} }
}

try {
    $result = Invoke-Scenario 'auth-missing'
    Assert-True ($result.ExitCode -ne 0 -and $result.Output.EndsWith('AUTHENTICATION_FAILED: FAILED')) 'Missing authentication was not categorized.'
    Assert-NotContains $result.Output 'ghp_SYNTHETIC_AUTH_CANARY' 'Authentication error leaked raw native output.'

    $result = Invoke-Scenario 'no-admin'
    Assert-True ($result.ExitCode -ne 0 -and $result.Output.EndsWith('AUTHORIZATION_FAILED: FAILED')) 'Insufficient repository permission was not rejected.'

    $result = Invoke-Scenario 'existing'
    Assert-True ($result.ExitCode -eq 0 -and $result.Output.Contains('ENVIRONMENT_FOUND') -and $result.Output.Contains('ENVIRONMENT_COMPLIANT')) 'Existing compliant Environment was not detected idempotently.'
    Assert-True (-not $result.Mutations) 'Read-only existing Environment check mutated GitHub.'

    $result = Invoke-Scenario 'missing'
    Assert-True ($result.ExitCode -eq 0 -and $result.Output.Contains('ENVIRONMENT_MISSING') -and $result.Output.Contains('PREVIEW_CHANGES_REQUIRED')) 'Missing Environment preview failed.'
    Assert-NotContains $result.Output 'synthetic-resource-canary' 'Missing Environment raw API output leaked.'
    Assert-True (-not $result.Mutations) 'Default preview mutated GitHub.'

    $result = Invoke-Scenario 'reviewers' @('-Reviewers','user:reviewer-one')
    Assert-True ($result.ExitCode -eq 0 -and $result.Output.Contains('REVIEWERS_VALIDATED') -and $result.Output.Contains('PROTECTION_SUPPORTED')) 'Optional reviewer validation failed.'
    Assert-True (-not $result.Mutations) 'Reviewer preview mutated GitHub.'

    $result = Invoke-Scenario 'unsupported' @('-Reviewers','user:reviewer-one')
    Assert-True ($result.ExitCode -ne 0 -and $result.Output.EndsWith('PROTECTION_UNSUPPORTED: FAILED')) 'Unsupported reviewer protection was silently accepted.'

    $result = Invoke-Scenario 'private-free'
    Assert-True ($result.ExitCode -ne 0 -and $result.Output.EndsWith('PROTECTION_UNSUPPORTED: FAILED')) 'Unsupported private-repository Environment was silently accepted.'

    $result = Invoke-Scenario 'whatif' @('-Apply','-WhatIf')
    Assert-True ($result.ExitCode -eq 0 -and $result.Output.Contains('PREVIEW_CHANGES_REQUIRED') -and -not $result.Mutations) 'WhatIf performed a mutation.'

    $confirmation = 'JoergBrors/PlaceHub/development/main'
    $result = Invoke-Scenario 'reviewers' @('-Reviewers','user:reviewer-one','-Apply','-ConfirmTarget',$confirmation)
    Assert-True ($result.ExitCode -eq 0 -and $result.Output.Contains('APPLY_COMPLETE')) 'Approved Environment creation scenario failed.'
    Assert-True ($result.Mutations.Contains('"custom_branch_policies":true') -and $result.Mutations.Contains('"prevent_self_review":true')) 'Environment payload lacks exact branch policy or self-review prevention.'
    Assert-True ($result.Mutations.Contains('POST|repos/JoergBrors/PlaceHub/environments/development/deployment-branch-policies|') -and $result.Mutations.Contains('"name":"main"')) 'Exact main branch policy was not created.'

    $result = Invoke-Scenario 'existing-wrong' @('-Apply','-ConfirmTarget',$confirmation)
    Assert-True ($result.ExitCode -eq 0 -and $result.Mutations.Contains('/deployment-branch-policies/77')) 'Unwanted branch policy was not removed in the reviewed apply scenario.'
}
finally {
    Remove-Item Env:PLACEHUB_GH_SCENARIO -ErrorAction SilentlyContinue
    Remove-Item Env:PLACEHUB_GH_MUTATION_LOG -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

Write-Host 'GitHub Environment synthetic tests passed.'
