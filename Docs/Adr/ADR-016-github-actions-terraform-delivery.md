# ADR-016: GitHub Actions Terraform Delivery

- **Status:** Accepted, amended
- **Priority:** P0
- **Original decision date:** 2026-10-31
- **Original approval authority:** Project Owner approval
- **Amendment date:** 2026-10-31
- **Amendment authority:** Project Owner approval

## Decision history

The original accepted decision established manual `workflow_dispatch`, GitHub OIDC, a dedicated Terraform deployment identity, Azure Blob remote state, environment-bound trust, exact saved-plan apply, sensitive-output suppression and identity separation. It required broad pre-execution approval and deferred a plan/apply split because saved plans can contain secrets.

This amendment preserves those delivery and security foundations but replaces the change-authorization rule. **Creation and modification of resources inside an already approved PlaceHub environment, resource inventory and permission policy are normal authorized operations. Deletion, destructive replacement, managed-access removal and unverifiable plans require explicit, auditable approval before execution.**

The amendment authorizes architecture and delivery design. It does not authorize a live apply, tenant mutation, new paid Azure resource or implementation of the revised workflow in this documentation task.

**Transition rule at amendment time:** the workflow did not yet perform structured or semantic classification. Therefore every then-current `operation=apply` was `UNKNOWN_OR_UNVERIFIABLE` and could not be dispatched until the classifier/policy and non-destructive exact-plan path were implemented and validated. The authorization record below documents the verified partial resolution; destructive and unknown apply remain suspended.

## Development provisioning authorization record

On 2026-10-31 the Project Owner explicitly authorized implementation of the amended create/update model for the `development` environment. The approved inventory is limited to the PlaceHub confidential web application and service principal, its exact localhost callback, three stable user application roles, and the isolated Microsoft 365 provisioning application and service principal. No separate backend registration is authorized for the server-side monolith. No paid Azure application resource, effective Graph/Exchange grant, directory role, app-role assignment, credential or certificate is authorized by this record.

The repository now contains policy version `2026-10-31.1`, a structured plan classifier and same-job exact-plan integrity verification. After those controls pass, `NO_CHANGE`, `CREATE_ONLY`, `UPDATE_ONLY` and `CREATE_AND_UPDATE` may use `operation=apply` in `development`. `DESTRUCTIVE_CHANGE` remains blocked because no protected exact-plan approval/retention mechanism exists. `UNKNOWN_OR_UNVERIFIABLE` fails closed. The earlier transition suspension is therefore resolved only for the four non-destructive classifications and this exact policy version; it remains in force for every destructive, unknown, out-of-policy or other-environment plan.

## Context

PlaceHub needs reproducible Azure and Microsoft Entra provisioning without long-lived CI credentials. Requiring individual approval for every create or update adds friction without distinguishing data-loss and access-removal risk. Terraform exposes structured plan actions that can distinguish ordinary create/update from actions containing `delete`, but some destructive semantic effects are represented as updates or occur outside normal plan actions. The workflow therefore needs both structural classification and an approved policy layer.

The initial application PoC remains local Docker/SQLite with zero incremental Azure cost. This ADR governs how future approved resources are delivered; it does not authorize Azure application hosting.

## Amended decision

After the one-time, explicitly confirmed local PowerShell 7 bootstrap, run Terraform through GitHub Actions with environment-bound OIDC federation and the dedicated deployment service principal. Store state in the private Azure Blob backend using Entra data-plane authorization. Keep the bootstrap, Terraform deployment, interactive web, runtime and Microsoft 365 provisioning identities separate.

Within an explicitly approved environment, resource-type allowlist, naming/location boundary, RBAC scope and Entra permission policy:

- `NO_CHANGE`, `CREATE_ONLY`, `UPDATE_ONLY` and `CREATE_AND_UPDATE` may apply without an individual human change approval after all policy/status checks pass.
- `DESTRUCTIVE_CHANGE` requires a separate auditable approval bound to the exact saved plan before apply.
- `UNKNOWN_OR_UNVERIFIABLE` fails closed and cannot apply.
- A plan containing both ordinary and destructive actions is entirely destructive.

`destroy` remains unavailable as a workflow operation. Direct state mutation, targeted removal, `terraform state rm/mv/push`, `import` outside the reviewed process, `-replace`, `-target`, `-refresh-only`, `-lock=false`, ad-hoc backend changes and apply without the saved plan are prohibited unless a separate recovery procedure is explicitly approved.

## Permitted create and update scope

Normal automation may create/update approved Azure resources and approved Entra application objects, associated service principals, application metadata, app roles, exact redirect URIs, declared API requirements and non-destructive configuration. This authority is bounded by reviewed code and policy; it is not permission to introduce a new resource family, environment, region, paid service, production target or privileged permission.

For Entra objects, Terraform may declare `required_resource_access` and manage applications/service principals it is authorized to own. Declaration does not grant effective application permission, delegated/admin consent, an Entra directory role or Exchange RBAC. Effective grants occur only where a previously approved immutable permission policy expressly allows them and the delivery identity has separately approved technical authority. Otherwise an authorized administrator acts outside routine Terraform.

Prefer `Application.ReadWrite.OwnedBy` with explicit ownership bootstrap and negative tests. Do not grant `Application.ReadWrite.All` unless owned-object management is proven insufficient and a new security amendment approves the exact need. Do not grant `AppRoleAssignment.ReadWrite.All` or equivalent privilege-escalation authority as a convenience. The Terraform identity never receives Exchange private-key access or becomes the web/runtime/provisioning identity.

## Plan classification

Generate one non-speculative saved plan with the pinned Terraform/providers and classify its structured JSON representation from `terraform show -json <saved-plan>`. The classifier validates the supported JSON `format_version`, Terraform version, expected root/module/resource types, environment and policy version before examining `resource_changes[].change.actions`.

| Observed managed-resource actions | Classification |
|---|---|
| Empty or only `no-op`/`read` | `NO_CHANGE` |
| One or more `create`, no `update` or `delete` | `CREATE_ONLY` |
| One or more `update`, no `create` or `delete` | `UPDATE_ONLY` |
| Both `create` and `update`, no `delete` | `CREATE_AND_UPDATE` |
| Any action list containing `delete`, including `delete,create` or `create,delete` | `DESTRUCTIVE_CHANGE` |
| Unknown action/version/schema, parse failure, missing fields, policy ambiguity or unapproved target | `UNKNOWN_OR_UNVERIFIABLE` |

The JSON and binary plan are sensitive. They remain in protected temporary storage and never enter logs, job summaries or ordinary artifacts. Routine output is limited to classification, non-sensitive action counts, policy version, commit/run/environment binding and cryptographic digests.

Structural actions are necessary but insufficient. The policy layer must classify as destructive or reject:

- removal or reduction of Azure/Entra/Exchange/GitHub role, permission, owner, credential or federated-trust entries, even when represented as `update`;
- provider fields whose update can erase data, rotate identity, recreate children, reset configuration or revoke access;
- database/storage retention, recovery, encryption, network or lifecycle changes with loss/lockout effects;
- removal from Terraform configuration/state, moved/import blocks not matching an approved migration, and orphaning/unmanagement;
- provider-version/schema changes without reviewed classifier fixtures;
- sensitive `before`/`after` values that the policy engine cannot safely interpret.

Every approved resource type needs versioned semantic policy tests. If semantic destructiveness cannot be determined reliably, the plan is `UNKNOWN_OR_UNVERIFIABLE` rather than automatically safe.

## Workflow and exact-plan approval design

The target design separates plan/classification from apply while preserving the exact binary plan:

1. Check out the immutable commit and validate branch, environment, repository, tenant/subscription, resource policy and zero-cost-PoC boundary.
2. Authenticate with environment-bound GitHub OIDC; initialize and validate Terraform.
3. Create one saved plan and immediately compute its SHA-256 digest.
4. Convert it to JSON only through a no-log pipe into the classifier; never persist or print JSON unless an approved encrypted mechanism requires it.
5. Produce a signed/attested non-sensitive manifest containing repository, commit SHA, workflow/run/attempt, environment, Terraform/provider lock digest, policy version, classification, action counts, plan digest and expiry.
6. For non-destructive categories, apply that exact saved plan in the same protected execution context after status/branch checks.
7. For destructive classification, stop before apply and require a protected approval tied to the manifest and binary plan.
8. Before destructive apply, verify every manifest binding and plan digest, reacquire the expected environment identity, and apply the same saved plan without replanning.
9. Remove plan/JSON/key material on success, failure and cancellation; runner disposal remains the final boundary.

The current workflow keeps the plan only in one ephemeral job. GitHub Environment approval occurs before that job starts and therefore cannot approve a plan that does not yet exist. An ordinary GitHub artifact is not approved for binary-plan transfer because saved plans can contain cleartext secrets.

Until an encrypted, access-controlled, short-retention plan store or an approved external run service is implemented and tested, destructive plans **must fail closed**. Acceptable future mechanisms must provide encryption with a separately controlled key, least-privilege readers, immutable digest/attestation, run/commit/environment binding, expiry, audited approval, replay prevention and verified deletion. Approval of a manifest without protected access to the exact corresponding plan is insufficient.

No destructive approval may trigger a replan. If the plan expires, state/configuration changes, binding verification fails or transfer is unavailable, discard it and start a new plan/approval cycle.

## GitHub and repository protections

- Keep GitHub OIDC with no long-lived deployment secret.
- Restrict the deployment environment to the exact approved branch and prevent self-review for destructive approval where supported.
- Protect infrastructure paths and classifier/policy/workflow code with CODEOWNERS or equivalent review, branch protection and required static/classifier/security checks.
- Pin action and tool dependencies; review updates.
- Treat pull-request review as code/policy authorization, not as approval of a later destructive plan.
- Emit no raw Terraform, JSON, state, environment or command output.
- Audit classification, approver identity, manifest digest, plan digest, apply result and recovery action without sensitive values.

## Alternatives considered

- **Approve every apply:** superseded; it does not distinguish ordinary changes from destructive risk.
- **Automatically apply every plan:** rejected; delete/replacement/access-removal requires explicit approval.
- **Replan after approval:** rejected; approval would not bind the applied actions.
- **Human-readable plan parsing:** rejected; console text is not the stable structured interface.
- **Ordinary GitHub artifact transfer:** rejected until confidentiality, integrity, access and deletion controls are approved.
- **Same-run protected external service/HCP Terraform:** feasible future candidates, but add cost/vendor/governance decisions and are not selected here.
- **Local destructive apply:** rejected as routine delivery; a separately authorized recovery procedure may be defined.

## Consequences and security implications

- Safe create/update throughput improves after policy validation.
- Classifier and provider-semantic policy become security-critical code and require adversarial fixtures.
- Destructive automation is unavailable until protected exact-plan retention is implemented; this is deliberate fail-closed behavior.
- A compromised Terraform identity can affect all resources inside its technical permissions. Azure scope, Entra ownership, branch protection and resource/permission policy remain mandatory even when changes need no individual approval.
- `Application.ReadWrite.OwnedBy` still permits sensitive operations on owned objects and listing directory applications/service principals; ownership bootstrap and drift require audit.
- Permission declaration is not consent. Effective privilege escalation remains outside general create/update authorization.
- Rollback often requires another forward plan and can itself delete/replace; it is classified normally and may require destructive approval.
- Partial apply can leave state/resources changed. Stop concurrent writers, preserve state, classify the recovery plan and use the incident procedure; never bypass approval by editing state.

## Zero-cost initial PoC boundary

No App Service, ACR, Key Vault, database, worker, monitoring, network or other Azure application resource is authorized for the local initial PoC. Entra application-management design can be prepared independently, but live objects/permissions are not changed by this documentation amendment. Existing remote-state infrastructure and its pre-existing cost remain unchanged.

## Validation requirements

Before workflow implementation or live use, prove with synthetic plans and provider-specific fixtures:

- each of the six classifications, including both replacement orderings and mixed actions;
- malformed/unknown JSON/version and unapproved resource/environment fail closed;
- role/permission/credential/owner removal expressed as update is destructive;
- data-loss provider updates and state-operation attempts are rejected;
- plan digest and repository/commit/environment/run/policy bindings cannot be substituted or replayed;
- non-destructive apply uses the exact classified saved plan;
- destructive apply cannot run without exact-plan approval and cannot silently replan;
- JSON/binary plans, state and secrets never reach logs or ordinary artifacts;
- OIDC issuer/audience/subject and least-privilege scopes remain exact;
- no initial-PoC Azure application resource can pass policy.

## Remaining implementation and approval gates

1. Review any expansion beyond development policy `2026-10-31.1`; no other environment/resource/permission is authorized.
2. Re-prove the classifier against every approved Terraform/provider/schema upgrade.
3. Select and approve protected plan retention/transfer; until then destructive plans are blocked.
4. Configure branch/CODEOWNERS/status/environment protections supported by the repository plan.
5. Approve Entra ownership bootstrap and exact `Application.ReadWrite.OwnedBy` provider-operation evidence before granting it.
6. Approve any effective Graph permission grant/consent, directory role or Exchange RBAC separately under its permission policy.
7. Retain explicit authorization for production environment creation/boundary and destructive production plans; ordinary in-boundary create/update then follows this ADR.
8. Define audited incident/state-recovery procedures that cannot bypass classification.

## Development architecture inventory amendment — 2026-11-01

Project Owner architecture approval expands the prospective development inventory to a dedicated Worker Key Vault and the exact worker-only `Key Vault Secrets User` assignment, managed by the existing Terraform root. It does not approve an unknown principal, network design, cost-incurring apply, certificate content, secret/certificate Terraform resource, Graph/Exchange consent or role assignment execution. The active policy may be expanded only after exact vault name, resource group, worker principal, network boundary and nonsecret outputs are reviewable. Any access removal remains destructive; unknown or out-of-policy plans fail closed.

## References

- [HashiCorp Terraform JSON output format](https://developer.hashicorp.com/terraform/internals/json-format)
- [HashiCorp `terraform show` and sensitive JSON warning](https://developer.hashicorp.com/terraform/cli/commands/show)
- [HashiCorp saved-plan confidentiality](https://developer.hashicorp.com/terraform/cli/commands/plan)
- [HashiCorp exact saved-plan apply](https://developer.hashicorp.com/terraform/cli/commands/apply)
- [GitHub deployment environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- [Microsoft GitHub OIDC authentication](https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect)
- [Microsoft workload identity federation](https://learn.microsoft.com/entra/workload-id/workload-identity-federation-create-trust?pivots=identity-wif-app-reg-github-actions)

