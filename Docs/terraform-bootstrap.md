# Terraform bootstrap and operations

## Status and trust boundaries

This implementation prepares the delivery foundation; it does not select PlaceHub hosting resources. ADR-016 is **Proposed** and requires approval. No command in this repository grants Graph admin consent, Exchange permissions, or performs `terraform apply` outside the manually dispatched workflow.

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
- Review and accept/reject ADR-016 and the approval gates below before a real run.

Copy `.env.example` to `.env` and enter identifiers. The parser accepts only `NAME=value`; it does not execute content. Do not place secrets in the file. Preview first:

```powershell
$target = '<tenant-guid>/<subscription-guid>/<owner/repo>/<environment>'
./scripts/Bootstrap-Terraform.ps1 -DryRun -ConfirmTarget $target -WhatIf
./scripts/Bootstrap-Terraform.ps1 -ConfirmTarget $target
```

`-DryRun` performs authentication and read checks but suppresses mutations. `-WhatIf` also protects every mutating command. The script is idempotent: it reuses uniquely named resources, verifies existing federated trust, and uses idempotent ARM/role assignment operations. Multiple same-name Entra apps stop execution.

The sanitized summary contains IDs and exact trust claims, never tokens, keys or state. Only the eight named non-secret configuration variables are uploaded; `.env` is never bulk-uploaded.

## GitHub and OIDC controls

The workflow has only `workflow_dispatch`, defaults to `plan`, requires selection of the target GitHub Environment, and exposes no destroy operation. It has `contents: read` and `id-token: write`, uses an environment-bound OIDC credential, pins tool/action versions, serializes runs per selected environment, and never uploads a plan artifact. Apply consumes the exact `tfplan` file created in the same job and run. The explicit environment input avoids a bootstrap paradox: environment-scoped variables are not available until GitHub has selected that environment.

Configure required reviewers and prevent self-review in **Settings → Environments → ENV** when the repository plan supports it. GitHub documents that required reviewers for private/internal repositories depend on the account plan; on several non-Enterprise plans those protection rules are public-repository-only. If reviewers are unavailable, `apply` lacks a four-eyes gate: do not authorize production apply until an equivalent control is approved.

Approval occurs before the environment job starts, so the reviewer cannot see the newly generated plan. Splitting plan/apply would require transferring the binary plan, which can contain secrets. Do not add an artifact until encryption, access, retention, commit/run binding and integrity verification (for example an attestation or independently checked SHA-256) are approved.

## State and recovery

- The `azurerm` backend uses OIDC plus Entra authorization; shared-key access is disabled and no SAS is used.
- `Storage Blob Data Contributor` is assigned at the container, the recommended narrow data-plane scope. The predictable standard blob endpoint avoids an extra management-plane Reader role.
- Azure Blob leases provide automatic Terraform state locking and consistency checking. Never use `-lock=false`. Use `force-unlock` only after proving the owning run is gone and recording the lock ID.
- Blob and container soft delete plus blob versioning are enabled for 30 days. Azure Storage charges for retained versions/capacity and transactions; GitHub-hosted runner/account charges depend on the repository plan. Resource groups, Entra apps and federated credentials have no direct charge.
- Enable Storage diagnostic settings to an approved Log Analytics workspace/archive once the monitoring destination and retention are decided. Azure Activity Log covers management operations; storage resource logs are needed for data-plane audit.
- State and plans can contain secrets even when outputs are marked sensitive. Limit state readers, never print `terraform state pull`, and do not upload plans/log full environment variables.

For recovery, inspect resources before rerunning; the script safely reuses matching resources. After a partial failure, fix the reported authorization/API error and rerun with the same confirmed values. If infrastructure already exists outside Terraform, add matching resource declarations and use `import` blocks or `terraform import`—never recreate it blindly. If remote state persistence fails and Terraform leaves local state, preserve it securely, stop all writers, compare lineage/serial, and follow HashiCorp state recovery guidance. Restore a prior blob version only during an incident with all runs stopped and an audited change record.

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

## Validation and failure exercises

Run locally without applying infrastructure:

```powershell
pwsh -NoProfile -File ./tests/Test-Static.ps1
terraform -chdir=infrastructure/terraform fmt -check -recursive
terraform -chdir=infrastructure/terraform init -backend=false
terraform -chdir=infrastructure/terraform validate
```

Cloud tests require explicit authorization and an approved test tenant: repeat bootstrap twice; try mismatched tenant/subscription/confirmation; revoke GitHub/API permission to confirm safe failure; dispatch plan; verify the OIDC subject; hold a state lease to test lock failure; confirm apply waits for environment approval; inspect logs/artifacts for credentials. Never use production for these tests.

## Official references

- [Azure Login with GitHub OIDC](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect)
- [Microsoft Entra federated credential trust](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust?pivots=identity-wif-app-reg-github-actions)
- [Terraform AzureRM backend and locking](https://developer.hashicorp.com/terraform/language/backend/azurerm)
- [Terraform state locking](https://developer.hashicorp.com/terraform/language/state/locking)
- [Microsoft Graph permission reference](https://learn.microsoft.com/en-us/graph/permissions-reference)
- [GitHub environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- [GitHub variables](https://docs.github.com/en/actions/concepts/workflows-and-actions/variables)
- [GitHub OIDC reference](https://docs.github.com/en/actions/reference/security/oidc)

