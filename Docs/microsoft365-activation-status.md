# Microsoft 365 activation status

**Assessment date:** 2026-11-01  
**Status:** BLOCKED – application hardened and verified locally; tenant-side declaration, consent, role assignment and web credential outstanding.

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

## Independent review 2026-11-01 (tenant `db88f9b6…`, subscription `d6743694…`, Azure CLI user session)

Azure CLI default context matches `.env` (tenant and subscription). Three further subscriptions in two other tenants are visible and were not touched. The default subscription was not changed. Tenant reads were Graph `GET` only.

| Item | Desired (repo) | Actual (tenant) | State |
|---|---|---|---|
| `placehub-frontend-development` app (`0f8f167f…`) | exists, AzureADMyOrg | exists, AzureADMyOrg | VERIFIED_IN_TENANT |
| App roles (3 stable IDs) | OfficeManager / LocationManager / SystemAdministrator | identical IDs | VERIFIED_IN_TENANT |
| Redirect URIs | `:3242` + legacy `:8443` | identical | VERIFIED_IN_TENANT |
| `required_resource_access` | `Calendars.ReadBasic` + `Place.Read.All` (Scope) | empty | BLOCKED_APPROVAL (Terraform apply) |
| Permission IDs | `662d75ba…` (User consent), `cb8f45a0…` (Admin consent) | match Graph service principal | VERIFIED_IN_TENANT |
| OAuth2 delegated grants | admin consent for `Place.Read.All` | none | BLOCKED_PERMISSION |
| App-role assignments (enterprise app) | approved Office Manager principal | none (`appRoleAssignmentRequired=true`) | BLOCKED_APPROVAL |
| Web client credential | public cert registered | no key or password credentials; no PFX in `PLACEHUB_TLS_DIRECTORY` | BLOCKED_CREDENTIAL |
| Provisioning app (`9ee67623…`) | no permissions, no roles | none | VERIFIED_IN_TENANT |
| Terraform delivery app | separate identity | separate; holds one Graph application role | VERIFIED_IN_TENANT |

Declared, consented, assigned, token-scope and successful-Graph-request states are tracked separately; only the first exists in the repository, none exists effectively in the tenant. The `PLACEHUB_*_VERIFIED=true` lines in the local `.env` are not read by any code and are not evidence; they should be removed or set to `false`.

### Defects fixed

- `CurrentActorContext` read `HttpContext`, which is `null` inside a Blazor Server circuit after prerender; it now falls back to the circuit authentication state. An unauthorized user no longer crashes component construction: denial is deferred to `Current` and rendered as a 403 state (`/auth/denied`).
- Graph Places keyed records by `placeId ?? id` while `parentId` references `id`. Records are now keyed by `id`, `placeId` is retained as the stable identifier, parents are normalized to either form, and `lastUpdatedTime` is carried as the source timestamp.
- Dashboard showed static “verifiziert / Verbunden / Live” labels; they are now derived from runtime state.
- Terraform plan classifier compared raw JSON strings of `required_resource_access`; Terraform emits keys alphabetically, so the first non-empty declaration was rejected as `APPLICATION_POLICY_MISMATCH` (workflow run `41288233698`, no apply, no change). Comparison is now canonical; regression case added.

### Verification

- `dotnet build -c Release` 0 warnings; 41 xUnit tests and all `tests/Test-*.ps1` pass (VERIFIED_LOCALLY).
- `terraform fmt -check` and `validate` pass locally (VERIFIED_LOCALLY).
- Docker: Live-First `placehub-web` fails closed with `CLIENT_CERTIFICATE_UNAVAILABLE` and no synthetic fallback; worker starts disabled with only the data volume mounted, no Docker socket, no published port (VERIFIED_LOCALLY).
- Plan via ADR-016 workflow on `main` (pre-fix): `UNKNOWN_OR_UNVERIFIABLE`, apply not attempted. Re-plan on the fix branch was rejected by `development` environment protection (main only). Re-plan is NOT_TESTED until the fix is merged to `main`.
- OIDC login, delegated token with `scp`, Places read, `getSchedule`: NOT_TESTED (blocked by the items above). No live success is claimed.

### Remaining approval gates (in order)

1. Review/merge `fix/live-read-hardening` into `main`; run workflow `operation=plan`; expect `UPDATE_ONLY` on `placehub_web` adding the two scopes; apply only after review (Project Owner).
2. Application Administrator / Cloud Application Administrator or Global Administrator: admin consent for delegated `Place.Read.All` on `placehub-frontend-development` only.
3. Enterprise application assignment of one approved user/group to exactly one PlaceHub role, plus the matching building Place ID in `PlaceHub:LocationAssignments:{oid}`.
4. Confirm credential owner and authority, run `scripts/Initialize-LocalEntraCertificate.ps1`, register only the public `.cer` on the web app (the Terraform policy currently forbids `key_credentials`; registration needs an ADR-016 policy amendment or a documented out-of-band step).
5. Ensure the approved identity has a mailbox/calendar and that resource mailboxes are readable for `getSchedule`.

ADR classification: Existing ADR Applies (ADR-004/005/007/009/016); the credential-registration route in step 4 is ADR Review Required against ADR-016. Worker, Key Vault and Exchange RBAC gates are unchanged and untouched.

## Gate-resolution pass (2026-11-01, second session)

| Operation | Basis | Outcome |
|---|---|---|
| Branch diff review (`origin/main..fix/live-read-hardening`) | task instruction | 11 intended files only |
| Pull request #1 opened into `main` | task instruction | OPEN; `main` has no branch protection and no configured required review or CI checks, so no authorized review path exists yet. Merge left to the Project Owner. |
| Local `.env`: removed `PLACEHUB_PERMISSIONS_APPROVED`, `_CONSENT_VERIFIED`, `_TENANT_CAPABILITY_VERIFIED` | task instruction; grep proved no reader | done (file is git-ignored) |
| Web certificate generation | `web_credential_strategy` is `PENDING` in the approval record | NOT executed (BLOCKED_APPROVAL) |
| Entra credential registration | requires explicit approval and ADR-016 review (policy forbids `key_credentials`) | NOT executed |
| Terraform re-plan | environment `development` accepts only `main` | NOT_TESTED until PR #1 is merged |
| Consent policy read (`authorizationPolicy`) | read-only | User consent policies assigned: `microsoft-user-default-recommended`, `-allow-consent-apps`. Whether `Calendars.ReadBasic` qualifies as low-impact under them is not established; `Place.Read.All` is Admin-only regardless. Consent-request policy not readable with this identity (403). |

Live validation (OIDC, `scp`, Places, `getSchedule`, negative cases) remains NOT_TESTED.
