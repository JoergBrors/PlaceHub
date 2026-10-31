# Terraform bootstrap and operations

## Status and trust boundaries

This implementation prepares the delivery foundation; it does not select PlaceHub hosting resources. ADR-016 is **Accepted**, by Project Owner approval dated 2026-10-31. Its acceptance approves the delivery architecture, not live permissions or deployments. No command in this repository grants Graph admin consent, Exchange permissions, or performs `terraform apply` outside the manually dispatched workflow.

Four identities must remain separate:

| Identity | Purpose | Persistent permission |
|---|---|---|
| Local bootstrap operator | Create the delivery foundation once | None added by the script; use eligible/admin access only for bootstrap |
| GitHub Terraform deployment service principal | Terraform through GitHub OIDC | Contributor on `rg-placehub-ENV`; Blob Data Contributor on the single state container; optional Graph permission only after approval |
| PlaceHub interactive application | User sign-in and runtime API calls | Defined later by ADR-009/capability discovery; never reuse the deployment identity |
| Microsoft 365 provisioning identity | Privileged Places/Exchange operations | Not created here; isolate and scope per ADR-015 and Exchange Application RBAC |

## Prerequisites and bootstrap

- PowerShell 7.2+, Azure CLI, GitHub CLI and Terraform 1.16.1; Python is optional.
- An approved test tenant/subscription and a GitHub repository you administer.
- The operator must be able to create resource groups/storage/RBAC in the selected subscription, create Entra applications and GitHub environments/variables. These are bootstrap permissions, not permissions assigned to PlaceHub.
- Review ADR-016 and obtain the separate permission and operational approvals below before a real run.

Copy `.env.example` to `.env` and enter identifiers. The parser accepts only `NAME=value`; it does not execute content. Do not place secrets in the file. Preview first:

```powershell
$target = '<tenant-guid>/<subscription-guid>/<owner/repo>/<environment>'
./scripts/Bootstrap-Terraform.ps1 -DryRun -ConfirmTarget $target -WhatIf
./scripts/Bootstrap-Terraform.ps1 -ConfirmTarget $target -ApproveWorkloadContributor
```

`-DryRun` performs authentication and read checks but suppresses the entire dependent mutation phase. `-WhatIf` has the same mutation guarantee. Neither mode substitutes placeholder identities or attempts downstream RBAC after a suppressed identity creation. The script is idempotent: it reuses uniquely named resources, verifies existing federated trust, and uses idempotent ARM/role assignment operations. Multiple same-name Entra apps stop execution.

Mutation mode additionally requires `-ApproveWorkloadContributor`. That switch records explicit operator authorization to assign Contributor on the single environment workload Resource Group; accepting ADR-016 does not supply this authorization. Use the switch only after the assignment has been approved through the applicable change/security process. It does not authorize production deployment.

Repairing an existing, mismatched federated credential additionally requires `-ApproveOidcCredentialRepair`. The switch authorizes only an in-place Microsoft Graph `PATCH` of the one uniquely named credential discovered for the target environment. The script does not create a second credential, broaden the issuer/audience, change GitHub OIDC settings, or proceed when duplicate named credentials exist. It reads the credential back and requires an exact match after repair.

Routine output is limited to allowlisted statuses such as `PREREQUISITES_OK`, `DISCOVERY_OK`, `PREVIEW_COMPLETE` and `BOOTSTRAP_COMPLETE`. Preview deliberately does not claim that no changes are needed: some write-only or permission-sensitive conditions are validated only during an authorized run. Failures contain only a stable category and `FAILED`. The script does not print identifiers, commands, argument arrays, native stdout/stderr, exception details, API bodies or a result object. Only the eight named non-secret configuration variables are uploaded; `.env` is never bulk-uploaded.

## GitHub and OIDC controls

The workflow has only `workflow_dispatch`, defaults to `plan`, requires selection of the target GitHub Environment, and exposes no destroy operation. It has `contents: read` and `id-token: write`, uses an environment-bound OIDC credential, pins tool/action versions, serializes runs per selected environment, and never uploads a plan artifact. Before authentication it requires the selected environment name to equal that environment's `TF_ENVIRONMENT` value. Apply consumes the exact saved plan created in the same job and run. The explicit environment input avoids a bootstrap paradox: environment-scoped variables are not available until GitHub has selected that environment.

The bootstrap queries the repository and its Actions OIDC subject settings without changing them. For the name-based default, the exact environment subject is `repo:JoergBrors/PlaceHub:environment:development`. GitHub repositories created after 2026-07-15, renamed or transferred after that date, or opted in use the immutable form `repo:OWNER@OWNER-ID/REPOSITORY@REPOSITORY-ID:environment:development`; the bootstrap obtains the numeric IDs from GitHub and constructs that exact value. A custom template is accepted only when its ordered claims are exactly `repo,context`, which retains the repository/environment boundary. Other templates fail closed with `OIDC_VALIDATION_FAILED`.

Terraform stdout/stderr is captured in memory and discarded; it is never echoed or saved as a diagnostic log. The workflow emits only formatting/init/validate/apply status and `Changes detected: yes|no`, derived from Terraform's documented `-detailed-exitcode`. It never runs `terraform show`, state commands, raw/JSON output commands, environment dumps or shell tracing. The plan is held under the runner temporary directory, removed after use and never uploaded. A GitHub-hosted runner is ephemeral, but neither the workflow nor GitHub exposes a verifiable physical-media secure erase primitive.

Configure required reviewers and prevent self-review in **Settings → Environments → ENV** when the repository plan supports it. GitHub documents that required reviewers for private/internal repositories depend on the account plan; on several non-Enterprise plans those protection rules are public-repository-only. If reviewers are unavailable, `apply` lacks a four-eyes gate: do not authorize production apply until an equivalent control is approved.

Approval occurs before the environment job starts, so the reviewer cannot see the newly generated plan. Splitting plan/apply would require transferring the binary plan, which can contain secrets. Do not add an artifact until encryption, access, retention, commit/run binding and integrity verification (for example an attestation or independently checked SHA-256) are approved.

### Initialize the development GitHub Environment

[`Initialize-GitHubEnvironment.ps1`](../scripts/Initialize-GitHubEnvironment.ps1) reproducibly inspects or configures the `development` Environment for `JoergBrors/PlaceHub`. It requires PowerShell 7, GitHub CLI authentication, and repository Admin permission. It uses GitHub REST API version `2026-03-10` through `gh api`; it never reads or changes Environment variables or secrets and never starts a workflow.

Default execution is read-only:

```powershell
./scripts/Initialize-GitHubEnvironment.ps1
./scripts/Initialize-GitHubEnvironment.ps1 -Reviewers user:octocat
./scripts/Initialize-GitHubEnvironment.ps1 -Reviewers team:JoergBrors/platform-reviewers
```

Reviewer specifications are `user:LOGIN` (a bare login is also accepted) or `team:ORGANIZATION/SLUG`, with GitHub's maximum of six. Users must have repository read access; teams must belong to the repository-owning organization and have repository access. When a new valid reviewer set is explicitly supplied, prevent-self-review is enabled. Existing reviewers, wait timers and custom protection rules are otherwise preserved. A requested reviewer change that differs from an existing reviewer set is rejected rather than potentially weakening protection.

After reviewing the preview, mutation requires both `-Apply` and the exact confirmation value. `-WhatIf` remains read-only even with `-Apply`:

```powershell
$confirmation = 'JoergBrors/PlaceHub/development/main'
./scripts/Initialize-GitHubEnvironment.ps1 -Apply -WhatIf
./scripts/Initialize-GitHubEnvironment.ps1 -Apply -ConfirmTarget $confirmation
```

The applied configuration permits only the exact `main` branch through a custom deployment branch policy. Other branch/tag policies are removed only in the explicitly confirmed apply operation; this narrows deployment eligibility. The script does not modify unrelated variables, secrets, or custom protection rules.

Required reviewers and prevent-self-review are plan-dependent. GitHub documents that on Free, Pro and Team plans they are available only for public repositories; private/internal use requires applicable Enterprise capability. The script fails with `PROTECTION_UNSUPPORTED` when requested support cannot be established and reports API refusal rather than silently omitting controls. Confirm current GitHub plan behavior before relying on reviewers.

This implements ADR-016's protected-environment foundation without changing its approval semantics. Environment reviewer approval occurs **before** the Terraform job and therefore before plan generation. It is not post-plan approval, and the approved architecture does not transfer a sensitive plan between jobs or runs.

## Safe logging and incident investigation

Permitted routine messages are the documented status strings, `Changes detected: yes|no`, and these categories: `PREREQUISITE_FAILED`, `AUTHENTICATION_FAILED`, `AUTHORIZATION_FAILED`, `REQUEST_INVALID`, `CONFIGURATION_INVALID`, `RESOURCE_CONFLICT`, `OIDC_VALIDATION_FAILED`, and the four `TERRAFORM_*_FAILED` operation categories. Do not enable PowerShell transcription, `Set-PSDebug`, Bash `set -x`, `TF_LOG`, Azure CLI log files, environment dumps or ad-hoc echo statements in routine runs.

GitHub `add-mask` is registered before third-party actions as secondary protection for known identifiers; it is not a secrecy guarantee. `actions/checkout`, `azure/login`, `setup-terraform`, the hosted runner and GitHub's own runner diagnostics remain trusted dependencies that can produce platform-controlled metadata. Review action updates before changing pinned versions.

For an authorized incident, correlate the workflow run ID and timestamp with GitHub audit/deployment history, Azure Activity Log, Entra sign-in/audit logs and approved Storage diagnostic logs. Restrict access through the incident role and record the investigation. Reproduce failures only in the approved test tenant with synthetic data. Do not turn on verbose/transcription/trace output, persist captured subprocess output, download state, or publish plan files. If vendor support requires sensitive evidence, use the organization's approved encrypted support channel and retention process outside routine Actions artifacts.

## State and recovery

- The `azurerm` backend uses OIDC plus Entra authorization; shared-key access is disabled and no SAS is used.
- `Storage Blob Data Contributor` is assigned at the container, the recommended narrow data-plane scope. The predictable standard blob endpoint avoids an extra management-plane Reader role.
- Azure Blob leases provide automatic Terraform state locking and consistency checking. Never use `-lock=false`. Use `force-unlock` only after proving the owning run is gone and recording the lock ID.
- Blob and container soft delete plus blob versioning are enabled for 30 days. Azure Storage charges for retained versions/capacity and transactions; GitHub-hosted runner/account charges depend on the repository plan. Resource groups, Entra apps and federated credentials have no direct charge.
- Enable Storage diagnostic settings to an approved Log Analytics workspace/archive once the monitoring destination and retention are decided. Azure Activity Log covers management operations; storage resource logs are needed for data-plane audit.
- State and plans can contain secrets even when outputs are marked sensitive. Limit state readers, never print `terraform state pull`, and do not upload plans or log environment variables. HashiCorp explicitly documents that saved plans include full configuration, planned values and input variables and can hold sensitive data in cleartext.

For recovery, inspect resources before rerunning; the script safely reuses matching resources. After a partial failure, fix the reported authorization/API error and rerun with the same confirmed values. If infrastructure already exists outside Terraform, add matching resource declarations and use `import` blocks or `terraform import`—never recreate it blindly. If remote state persistence fails and Terraform leaves local state, preserve it securely, stop all writers, compare lineage/serial, and follow HashiCorp state recovery guidance. Restore a prior blob version only during an incident with all runs stopped and an audited change record.

### Bootstrap troubleshooting and partial recovery

If a run previously stopped after `DISCOVERY_OK`, update to the corrected bootstrap before retrying. Two Windows PowerShell/Azure CLI boundary defects were identified:

1. The former container URL expression placed `?` immediately after an unbraced PowerShell variable; PowerShell interpreted it as part of the variable reference and removed the ARM resource path. The script now builds and validates the URL as `https://management.azure.com${containerScope}?api-version=2023-05-01` before passing it as one Azure CLI argument.
2. Passing JSON inline in the native argument array allowed the Windows native-command quoting layer to remove embedded double quotes. Azure received `{properties:{publicAccess:None}}` instead of valid JSON and returned `RequestIsNotValidJson`. Both the container body and federated-credential body now use Azure CLI's supported `--body @file` convention, which bypasses shell JSON interpretation.

A separate PowerShell interpolation defect affected the OIDC subject. In `"repo:$Repository:environment:$Environment"`, PowerShell parsed `$Repository:environment` as a scope-qualified variable reference instead of the repository value followed by literal text. Because that variable did not exist, the generated value collapsed to `repo:development`. Subject construction now uses the format operator and exact-value tests cover both GitHub subject formats.

For every JSON REST mutation, the script validates the JSON, creates a uniquely named directory under the operating-system temporary directory, writes UTF-8 without a byte-order mark, passes the file as a single `@path` argument, and removes both file and directory in `finally`. On non-Windows platforms the file mode is restricted to the current user. The body and temporary path are never logged. A failed HTTP 400 request is categorized as `REQUEST_INVALID`, not as an authorization failure; raw Azure responses remain suppressed.

The bootstrap is safe to retry after the known partial state where the state Resource Group and secured Storage Account exist but the `tfstate` container and workload Resource Group do not. It reuses the existing Resource Group and Storage Account, idempotently creates/updates the private ARM container, reapplies blob recovery properties, reuses or creates the dedicated Entra application/service principal, then creates the missing workload Resource Group and approved scoped assignments. It does not enable shared-key or public access.

Preview the recovery first, then retry with the same confirmed values and the still-required Contributor approval:

```powershell
./scripts/Bootstrap-Terraform.ps1 -DryRun -ConfirmTarget $target -WhatIf
./scripts/Bootstrap-Terraform.ps1 -ConfirmTarget $target -ApproveWorkloadContributor
```

If preview emits `OIDC_REPAIR_REQUIRED`, obtain specific approval to replace the incorrect trust value, then use both approval switches:

```powershell
./scripts/Bootstrap-Terraform.ps1 -DryRun -ConfirmTarget $target -WhatIf
./scripts/Bootstrap-Terraform.ps1 -ConfirmTarget $target -ApproveWorkloadContributor -ApproveOidcCredentialRepair
```

The repair patches the existing `github-development` credential in place and verifies its exact issuer, subject and sole audience. Do not delete it manually or create a second credential. The operation requires the operator's existing Entra application-write authority; it does not grant Graph permissions or admin consent. If GitHub authentication cannot read the repository OIDC configuration, or if the template is not the accepted repository/environment form, execution stops before mutation.

Routine errors remain sanitized. A malformed internally constructed ARM URL is `CONFIGURATION_INVALID`; an Azure HTTP 400 payload/request rejection is `REQUEST_INVALID`; Azure CLI authentication failures remain `AUTHENTICATION_FAILED`; Azure API/RBAC failures are `AUTHORIZATION_FAILED`; OIDC trust mismatches remain `OIDC_VALIDATION_FAILED`. Native output and identifiers are not printed. For detail, use the authorized audit-log incident process rather than enabling command tracing or transcription.

## Permission matrix and unresolved decisions

| Plane | Permission | Scope | Why / status |
|---|---|---|---|
| Azure ARM | Contributor | Approved workload resource group only | Create/update application Azure resources; excludes RBAC assignment. Approval gate because final resource set is not yet defined. |
| Azure Storage data | Storage Blob Data Contributor | Exact state container | Read/write/delete state and acquire blob lease. Required. |
| Azure ARM | Reader | Storage account | Not assigned; only needed if backend blob endpoint lookup is enabled. |
| Microsoft Graph | `Application.ReadWrite.OwnedBy` application permission | Tenant directory, effective only for owned apps/SPs | Candidate if Terraform must create/manage PlaceHub app registrations. Requires admin consent and careful ownership bootstrap. Not assigned. It still permits listing apps/SPs and credential management for owned objects. |
| Microsoft Graph | `Application.ReadWrite.All` | Tenant directory | Broad fallback; not approved and must not be granted without architecture/security approval. |
| Microsoft Graph | `AppRoleAssignment.ReadWrite.All` | Tenant directory | Needed for some API permission grants/app-role assignments; highly privileged and can elevate applications. Not approved; keep consent/provisioning outside routine Terraform unless separately designed. |
| Exchange Online | Application RBAC management role | Scoped management scope | Only if a separate provisioning identity manages mailboxes. Not part of Terraform deployment identity and not configured. |
| GitHub | `id-token: write`, `contents: read` | Single workflow job/repository | Obtain OIDC token and read source. No write token permission. |

The AzureAD provider uses Microsoft Graph. The least-privilege feasibility of owned-object management, service-principal ownership, app roles and consent must be proven in the approved test tenant before adding any `azuread_*` resources. Terraform cannot turn ARM RBAC into directory permission, and neither grants Exchange authorization.

## Remaining approval requirements

ADR-016 acceptance leaves these gates open:

- **Workload Resource Group Contributor:** approve the exact environment Resource Group assignment before using `-ApproveWorkloadContributor`.
- **Terraform management of Entra applications:** approve the resource scope, ownership lifecycle and provider design before adding `azuread_*` resources.
- **Microsoft Graph admin consent:** not granted by bootstrap; requires separate privileged approval and execution.
- **GitHub Environment reviewers:** verify repository-plan support, configure required reviewers and prevent self-review where required before relying on a four-eyes control.
- **Production:** separately authorize the production environment bootstrap and every production apply under the operating change process.
- **Future post-plan approval:** requires an approved confidential plan-transfer, integrity, retention and cleanup design. The accepted workflow currently has only pre-plan Environment approval.

## Validation and failure exercises

Run locally without applying infrastructure:

```powershell
pwsh -NoProfile -File ./tests/Test-Static.ps1
pwsh -NoProfile -File ./tests/Test-GitHubEnvironment.ps1
terraform -chdir=infrastructure/terraform fmt -check -recursive
terraform -chdir=infrastructure/terraform init -backend=false
terraform -chdir=infrastructure/terraform validate
```

Cloud tests require explicit authorization and an approved test tenant: repeat bootstrap twice; try mismatched tenant/subscription/confirmation; revoke GitHub/API permission to confirm safe categorized failure; dispatch plan; verify the exact OIDC issuer, repository/environment subject, single audience and expected application; hold a state lease to test lock failure; confirm environment approval occurs before plan generation; inspect logs/artifacts using synthetic canaries. Never use production for these tests.

## Official references

- [Azure Login with GitHub OIDC](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect)
- [Microsoft Entra federated credential trust](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust?pivots=identity-wif-app-reg-github-actions)
- [Terraform AzureRM backend and locking](https://developer.hashicorp.com/terraform/language/backend/azurerm)
- [Terraform state locking](https://developer.hashicorp.com/terraform/language/state/locking)
- [Microsoft Graph permission reference](https://learn.microsoft.com/en-us/graph/permissions-reference)
- [GitHub environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- [GitHub variables](https://docs.github.com/en/actions/concepts/workflows-and-actions/variables)
- [GitHub OIDC reference](https://docs.github.com/en/actions/reference/security/oidc)
- [GitHub REST API: Actions OIDC subject customization](https://docs.github.com/en/rest/actions/oidc)
- [Microsoft Graph: update a federated identity credential](https://learn.microsoft.com/en-us/graph/api/federatedidentitycredential-update?view=graph-rest-1.0)
- [GitHub workflow commands and masking](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands)
- [Terraform plan command and saved-plan confidentiality](https://developer.hashicorp.com/terraform/cli/commands/plan)
- [GitHub REST API: deployment environments](https://docs.github.com/en/rest/deployments/environments)
- [GitHub REST API: deployment branch policies](https://docs.github.com/en/rest/deployments/branch-policies)
- [Azure CLI quoting and the `@file` JSON convention](https://learn.microsoft.com/en-us/cli/azure/use-azure-cli-successfully-quoting)
- [Azure CLI `az rest` reference](https://learn.microsoft.com/en-us/cli/azure/reference-index#az-rest)

