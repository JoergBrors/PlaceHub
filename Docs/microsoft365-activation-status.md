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

## Identity, location and credential package (2026-11-01, third session) {#identity-location-credential-package}

Project Owner selections authorize preparation and read-only discovery only. Nothing below was applied.

### Read-only tenant evidence

| Check | Result |
|---|---|
| Tenant | `db88f9b6…` matches `.env` – VERIFIED_IN_TENANT |
| Test user | `joerg@brors.net`, Member, enabled; Object ID `d085818d-dc3f-4c0c-8b3d-970ad5477bf6` resolved via Graph `users` lookup and confirmed by `signed-in-user` (not inferred from the name) |
| Enterprise app | SP `bac9ef95…`, client ID `0f8f167f…`, `appRoleAssignmentRequired=true` |
| Role `PlaceHub.SystemAdministrator` | `9a3f940c-08c4-4bd7-8cfa-106eaab349a5`, `allowedMemberTypes=User`, enabled |
| Current assignments | none (re-verified earlier this day; unchanged) |
| Building discovery | **BUILDING_DISCOVERY_BLOCKED_PERMISSION**: Azure CLI Graph token is rejected (401) by `/places/microsoft.graph.building`. The CLI session is not the PlaceHub app and proves nothing about its grants. Unblock: after admin consent for `Place.Read.All`, sign in once as the user and read the Dashboard, or an administrator with Places read lists buildings and supplies the `placeId`. |
| Tenant consent policy | `authorizationPolicy` readable: user-consent policies `microsoft-user-default-recommended` and `-allow-consent-apps`. Low-impact status of `Calendars.ReadBasic` under them is not established; consent-request policy returned 403 → **TENANT_CONSENT_POLICY_NOT_VERIFIED** |

### Prepared (not applied)

- Role assignment: `proposed_assignments[0]` in `infrastructure/terraform/proposals/development-app-role-assignments.json` (user → `PlaceHub.SystemAdministrator`, create). `effective_assignment_authorized=false`. An assignment does not grant a location.
- Location assignment: key `PlaceHub:LocationAssignments:d085818d-…` (set through `PLACEHUB_USER_OBJECT_ID` / `PLACEHUB_LOCATION_PLACE_ID` in the git-ignored `.env`) stays **unset** until the Owner picks a building `placeId`. Code denies a user without a location (`LOCATION_ASSIGNMENT_MISSING`); `SystemAdministrator` is an application role only and never implies tenant-wide access.
- Consent request: delegated `Place.Read.All` (Admin) for `placehub-frontend-development` only; no `Calendars.ReadWrite`, no application permissions.

### Web certificate review (script `scripts/Initialize-LocalEntraCertificate.ps1`, NOT executed)

RSA 3072, SHA-256, EKU clientAuth, CN `PlaceHub Development Web Authentication`, 180 days, PFX with empty password (acceptable only for a local read-only bind mount; the file ACL is the protection), `.cer` exported separately. The script now also restricts the PFX ACL to the current user on Windows (previously only `chmod` on Linux). .NET loads the PFX on Linux; the web container has no Key Vault access and the worker certificate is not reused. Rotation: regenerate ≥30 days before expiry, register the new `.cer`, then remove the old one. Runbook: generate → verify thumbprint/expiry → administrator registers `.cer` only → set `Microsoft365__ClientCertificates` path → restart web.

### ADR-016 credential ownership assessment

- Policy and classifier require **no** `key_credentials` on the web app; Terraform governance forbids certificate resources in the allowlist.
- A. Terraform-managed public certificate (`azuread_application_certificate`): auditable, but needs allowlist, policy and classifier changes and an ADR-016 amendment. Rejected for now.
- B. **Recommended:** administrator registers the public `.cer` outside Terraform. `azuread_application` does not reconcile credentials added this way, so no destructive plan is expected, but this must be proven: run `operation=plan` immediately after registration and confirm `NO_CHANGE` (the classifier's `key_credentials` check could otherwise trip on a computed attribute). Consequences: manual rotation with a recorded owner and expiry alert; credential is invisible to Terraform state.
- C. No documented alternative exists in the repository.
- Status: **ADR Review Required** (record approach B and the post-registration plan check in ADR-016; no policy change made). Registration is BLOCKED_APPROVAL.

### Personal-data classification

ADR-010 accepts SQLite for synthetic data only. The location mapping lives in configuration (`.env`), not SQLite, so nothing real is persisted in the database. Storing a real user Object ID in any database or tracked file needs **ADR Review Required** (ADR-009/010); the Object ID above is recorded here and in the proposal manifest as non-secret evidence only.

### Final checklist

User/OID verified; role verified; assignment PREPARED_NOT_APPLIED; building PENDING_OWNER_SELECTION; location PREPARED_NOT_APPLIED; certificate NOT_EXECUTED; registration BLOCKED_APPROVAL; plan NOT_TESTED (PR #1 unmerged; mergeable and clean, no required checks or reviews); apply NOT_EXECUTED; consent NOT_GRANTED; login, Places, `getSchedule` NOT_TESTED.

## ADR acceptance (2026-11-01)

The Project Owner accepted the ADR-004, ADR-005, ADR-015 and ADR-017 amendments as **target architecture** (wording: "ADR-004, ADR-005, ADR-015 und ADR-017 als Zielarchitektur freigeben, ohne operative Rechtefreigabe"). This supersedes the earlier "PROPOSED" statements in this document. Accepted: Graph v1.0 for Places hierarchy writes through the isolated worker, hierarchy and identifier rules, the BootstrapBuilding conditions, the typed request contract and the mandatory requester/approver separation. **Not approved, still BLOCKED_APPROVAL:** `Place.ReadWrite.All` and its consent, Exchange RBAC (`TenantPlacesManagement`, `MailRecipient`; assignability unproven), Terraform declarations and apply, worker identity, certificate and Key Vault access, worker activation, automatic workspace/desk mailbox creation, the bootstrap manifest content and every tenant write. Places write management remains NOT_TESTED and not operational.

## Places inventory diagnosis (2026-11-01)

Observed evidence (administrator delegated Graph reads): `places/microsoft.graph.building`, `floor` and `section` returned empty collections while `GET places/{id}` returned the building (`HomeOffice`, `id` equals `placeId`) and the section `Links`; `places/microsoft.graph.room` listed one room whose `parentId` is that section. The Places administration shows the same building. Classification: **INCONSISTENT_DIRECTORY_STATE** (resource readable by id, absent from the typed list). A propagation or index delay is plausible but **not proven**; no completion signal is exposed by Graph.

Implemented: `PlacesDiagnosticsService` (single bounded pass, counts and states only, never details of unauthorized resources) with the outcomes VerifiedEmpty, ResourceFound, PermissionDenied, TenantMismatch, ApiUnsupported, PendingPropagation (only with evidence from a previous inconsistent run), InconsistentDirectoryState and Unknown; shown on the Integration & Diagnose page. The reader resolves assigned buildings and missing ancestors by id (bounded), so the dashboard no longer depends on lagging lists. VERIFIED_LOCALLY (156 tests); the tenant result of the new page is NOT_TESTED until run by an operator.

## Parking booking contract (2026-11-01)

Graph v1.0 contract (Microsoft Learn): create `POST /me/events` (resource attendee, `transactionId` for idempotency), cancel by the organizer `POST /me/events/{id}/cancel`, update `PATCH`; least privileged permission is delegated `Calendars.ReadWrite`. Implemented and tested offline behind **closed gates** (`BookingOptions.WritesEnabled=false`, `DelegatedWriteScopeApproved=false`): `GraphBookingClient`, `ParkingReservationService` (location-scoped, verified-space only, interval/time-zone/lead-time validation, advisory `getSchedule` pre-check that blocks Busy/Unknown, local overlap guard, idempotency key, organizer-only cancel) and the states Pending, Accepted, Declined, Cancelled, Unknown, RequiresReconciliation. A created event is only **Pending**; **Accepted** exists only after the resource attendee response was read back; ambiguous writes become RequiresReconciliation and are never retried; external Outlook cancellation or removal is reconciled; a read failure never downgrades an accepted reservation. The web application token provider still refuses `Calendars.ReadWrite` (tested), so no booking write can occur until ADR-007 booking semantics, delegated-scope consent and the allowlist change are separately approved. Live Exchange acceptance behavior is **NOT_TESTED**.

## Parking UI and requirements commands (2026-11-01)

UI: `/parkplatz-verwaltung` (register an existing resource mailbox, category, accessibility and EV metadata, booking-policy and disable requests as typed approval-gated requests, business status mirrored from worker results only) and `/parkplatz-reservierungen` (request, status refresh from Exchange, cancel; writes are shown as **gesperrt** while `PlaceHub:Booking:WritesEnabled` and `PlaceHub:Booking:DelegatedWriteScopeApproved` are false, which is the default). The approvals page now shows Exchange and Places details. Business metadata is PlaceHub-owned and in-memory (development only); Exchange stays authoritative for availability and reservations. Raw Graph or PowerShell errors are never shown; known codes map to German messages.

Central script additions: `CheckConsent`, `CheckWorkerIdentity`, `CheckParkingMailboxes`, `DiagnosePlacesHierarchy` (single pass through an existing Graph PowerShell session, GET-only URL allowlist, `-PlaceId` validated), `ValidateTerraform`, `PrepareTerraformPlan`, `PrepareRoleAssignments`, `PrepareParkingProvisioning`. None opens an Exchange or Graph session, none mutates a tenant. Tests: `tests/Test-Requirements.ps1`. Live behavior of the new pages is NOT_TESTED.
