# Microsoft 365 activation status

**Assessment date:** 2026-11-01  
**Status:** Prepared locally; activation blocked by explicit approval and environment prerequisites.

| Area | Current evidence | Status |
|---|---|---|
| Active Terraform Graph/Exchange declarations | Both active `required_resource_access` inventories are empty | Not applied |
| Permission proposal | Exact IDs/types pass local proposal validation | Proposed only |
| Admin consent | No consent operation executed or inferred | Not granted/verified |
| App roles | Three stable Terraform role IDs; assignment required | Definitions prepared |
| Role assignments | Assignment proposal contains no identities | Not assigned by this work |
| Web credential | No approved certificate/provider configuration | Blocked |
| Live-first runtime | Live mode fails closed; explicit synthetic PoC profile remains accepted baseline | Not activated |
| Key Vault | Worker principal, network path and cost decision missing | Not planned/applied |
| Exchange RBAC | Interface and residual create privilege unresolved | Not configured |
| Live connectivity | No authorized tenant/test identity supplied | Not tested |
| Terraform validation | Terraform CLI unavailable in the local execution environment | Unverified |
| Terraform plan/apply | No active change and no apply authorization | Not run |

## Approval artifacts

- `infrastructure/terraform/proposals/development-m365-permissions.json`
- `infrastructure/terraform/proposals/development-activation-approval.json`
- `infrastructure/terraform/proposals/development-app-role-assignments.json`
- `Docs/Adr/live-first-approval-package.md`

The activation approval record must identify the exact tenant, accepted ADR decisions, approved permission subset, web credential strategy, Exchange interface, worker host/principal, Key Vault network model, cost approval, approvers and approval reference. The assignment manifest must identify exact user/group object IDs and corresponding location authorization. Neither file is connected to active Terraform.

## Safe next execution order

1. Record Project Owner and security decisions in the approval artifact through normal review; do not self-approve through Terraform.
2. Install the pinned Terraform CLI in an approved toolchain and run backend-disabled initialization plus validation.
3. Only after permission-policy approval, translate the approved subset into active Terraform and classifier fixtures.
4. Run manual workflow `operation=plan`; review the sanitized classification and keep the saved plan private.
5. Do not apply until the plan is within the exact approved inventory/policy and all required authorization is recorded.
6. Consent and app-role assignments remain separate administrator actions bound to reviewed manifests.
7. Run read-only tenant verification, then positive and negative non-production live-read tests.
8. Provisioning, Exchange RBAC, Key Vault access and worker execution remain disabled until their independent gates pass.
