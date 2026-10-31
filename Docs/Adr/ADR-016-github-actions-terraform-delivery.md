# ADR-016: GitHub Actions Terraform Delivery

- **Status:** Accepted
- **Priority:** P0
- **Date:** 2026-10-31
- **Approval date:** 2026-10-31
- **Decision authority:** Project Owner approval

## Context

PlaceHub needs reproducible Azure and Microsoft Entra provisioning without long-lived CI credentials. ADR-004, ADR-009 and ADR-015 require separate identities and least privilege; ADR-013 leaves the application hosting target open.

## Decision

After a one-time, explicitly confirmed local PowerShell 7 bootstrap, run Terraform exclusively in a manually dispatched GitHub Actions workflow. Authenticate with an environment-bound GitHub OIDC subject and Microsoft Entra workload identity federation. Store state in a private Azure Blob container using Entra data-plane authorization. Keep the local privileged bootstrap identity, GitHub deployment identity, PlaceHub interactive identity and any Microsoft 365 provisioning identity separate.

Use one workflow run to create and, for an `apply` dispatch, apply the exact local saved plan. Do not publish the binary plan because plans can contain cleartext sensitive values. Do not render the plan, state, raw outputs or raw Terraform diagnostics in routine logs. Emit only an allowlisted change/no-change result and stable failure categories. A protected GitHub Environment gates the job where the repository plan and account support it.

## Alternatives considered

- Local Terraform: rejected after bootstrap because execution and approval are not centrally auditable.
- Client secrets: rejected because workload identity federation avoids long-lived credentials.
- Plan artifact passed to a later run/job: deferred because a Terraform plan can expose secrets and artifact protection/attestation policy has not been approved.
- Terraform Cloud/Enterprise: not selected; it adds a service and commercial/governance decision not currently required.

## Consequences

- Environment approval happens before the job creates its plan. Reviewers cannot inspect that run's plan before approval without an approved protected artifact or external run service.
- The saved plan remains only in the ephemeral runner temporary directory and is removed on normal, failure and cancellation cleanup where GitHub permits cleanup to run. Runner disposal is the final isolation boundary; secure physical-media erasure is not exposed by GitHub-hosted runners.
- `workflow_dispatch` is the only trigger; `destroy` is not exposed.
- GitHub Environment reviewer availability depends on repository visibility and account plan.
- AzureRM management permissions and Entra/Graph permissions remain distinct. Graph admin consent is a separate approval gate.
- ADR-013 remains open: this decision governs provisioning delivery, not the eventual hosting choice.

## Security implications

The federated credential has exact issuer `https://token.actions.githubusercontent.com`, audience `api://AzureADTokenExchange`, and subject `repo:OWNER/REPOSITORY:environment:ENVIRONMENT`. Azure Contributor is limited to the approved workload resource group; Blob Data Contributor is limited to the state container. No storage keys, SAS tokens, client secrets, Graph admin consent, or Exchange permissions are created.

The workflow must bind the selected GitHub Environment to its environment-scoped `TF_ENVIRONMENT` value before authentication. Identifier masking is registered before third-party actions run, but masking is only defense in depth: application-controlled steps prevent sensitive command output from being emitted in the first place. Third-party actions and the hosted runner remain residual logging trust dependencies.

## Approval gates

Acceptance of this ADR approves the delivery architecture only. It does **not** approve a live bootstrap, a deployment, or any of the permissions below. These remain separate operational/security decisions:

1. Approve the workload resource-group Contributor assignment before running bootstrap in mutation mode.
2. Decide whether Terraform will manage Entra applications and, if so, approve a tested Graph permission/ownership model.
3. Grant Microsoft Graph admin consent only through a separate, explicitly approved privileged process.
4. Confirm GitHub plan/features support required reviewers, or approve an alternative control.
5. Explicitly authorize each production bootstrap and deployment according to the operating change process.
6. Approve a protected plan-transfer and integrity design before introducing any post-plan approval workflow split across jobs or runs.

## References

- [Microsoft: GitHub OIDC authentication](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect)
- [Microsoft: workload identity federation trust](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust?pivots=identity-wif-app-reg-github-actions)
- [HashiCorp: AzureRM backend](https://developer.hashicorp.com/terraform/language/backend/azurerm)
- [GitHub: deployment environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)

