# Live-first architecture approval package

**Status:** Project Owner architecture approval recorded 2026-11-01; no effective permission, consent, production processing or Terraform apply is authorized.

## Recorded architecture decision

Normal development execution is Live-First and fails closed; synthetic mocks are test-only. The established Entra roles, isolated worker, single-instance durable development queue, Exchange Online PowerShell provisioning interface and worker-only Terraform-managed Key Vault/RBAC boundary are approved. The web process has zero Key Vault access.

## Requested decisions

1. **ADR-004:** accept Graph v1.0 Places reads and delegated getSchedule; decide whether delegated calendar writes enter scope.
2. **ADR-005:** accept native Places hierarchy and keep workspace mutation method unresolved until test-tenant evidence.
3. **ADR-006/007:** decide parking mailbox type and delegated booking semantics.
4. **ADR-009 amendment:** replace mock-default normal execution with fail-closed single-tenant OIDC/Graph live execution; keep an explicitly enabled synthetic profile for tests only.
5. **ADR-011:** accept on-demand reads, bounded retry and explicit unavailable/stale states.
6. **ADR-013 amendment:** define which local runtime is “normal”, its approved credential store, TLS and operational ownership without adding paid Azure resources.
7. **ADR-015/017:** accept isolated worker and durable queue contracts before implementation.
8. **ADR-016 permission-policy authorization:** approve exact proposed declarations, policy version and whether declaration updates require an additional approval despite being structurally non-destructive.

## Permission declaration proposal

The inactive manifest at `infrastructure/terraform/proposals/development-m365-permissions.json` records exact resource applications, immutable IDs and delegated/application types. It is deliberately outside the Terraform root configuration. Moving it into `entra-applications.tf` and active policy is a separate reviewed change after approval. Declaration does not grant consent, Exchange RBAC, directory role, app-role assignment or certificate.

## Exchange evidence decision

Microsoft currently documents `Exchange.ManageAsApp` for app-only Exchange Online PowerShell and also documents `Exchange.ManageAsAppV2` for the newer Exchange Online Admin API. PlaceHub must select the actual execution interface and verify the corresponding tenant service-principal role ID before configuration. The existing ID must not be silently replaced or combined with a broader permission.

## Approval record required

Record Project Owner, security and operations decisions with date, target tenant/environment, exact permission-manifest digest, credential strategy, consent authority, role-assignment manifest, Exchange RBAC scope, worker host and mailbox-create residual-risk disposition. Until then, normal runtime remains the accepted explicit OfflineMock PoC profile and live mode fails closed.


## Live activation readiness – approval package (2026-11-01)

Separates three different kinds of approval. Approving one never implies another.

### A. Architecture decisions (recommendations, no effect on the tenant)

| Decision | Status | Recommendation |
|---|---|---|
| ADR-004/005/015/017 Places write path, four-eyes | **Accepted** (target architecture, 2026-11-01) | none open |
| ADR-006 parking mailbox model | **Proposed** | Equipment mailbox; administrators create mailboxes first, PlaceHub imports and configures (no `New-Mailbox` right in release 1); disable = PlaceHub-level first; templates `standard` and `restricted`; details in ADR-006 |
| ADR-007 booking writes | **Proposed** | accept delegated organizer-based booking for development with the documented residual risk; Pending/Accepted state model |
| ADR-010 persistence | Accepted for synthetic data only | amendment needed before real parking or reservation data is stored (currently in-memory) |
| ADR-009 location assignment | Accepted | location assignment currently travels through the git-ignored `.env`; no database of user identifiers |

### B. Permission grants (each separate, none executed)

| Grant | Identity | Exact id | Risk | Prerequisite |
|---|---|---|---|---|
| Delegated `Calendars.ReadWrite` | web app | `1ec239c2-d7c9-4623-a91a-a9775856bb36` | write access to all of the user's calendar events | ADR-007, ADR-016 declaration, token allowlist change |
| Application `Place.ReadWrite.All` | worker app | `f1f5e9aa-ad18-4b97-883e-6aa7e95b7a5f` | tenant-wide Places writes; Exchange scopes do not narrow it | ADR-016 policy amendment, consent, Exchange RBAC proof |
| Exchange RBAC `TenantPlacesManagement` + `MailRecipient` | worker service principal | – | `MailRecipient` manages users and mailboxes; assignability and scope **unproven** (not listed as supported application roles) | security review, clean-room proof |
| `Exchange.ManageAsApp` (Office 365 Exchange Online) | worker app | `dc50a0fb-09a3-484d-be87-e023b12c6440` | Exchange PowerShell as the app; effective rights come only from the assigned custom role group | ADR-006 creation model decision, ADR-016 |
| Web certificate registration | web app | – | done out-of-band (ADR-016 option B); verified matching thumbprint | – |
| Worker certificate registration | worker app | – | separate CSP RSA certificate (CNG unsupported for Exchange app-only) | worker identity approval |

Frontend `Place.Read.All` and `Calendars.ReadBasic` are already consented (VERIFIED_IN_TENANT).

### C. Live mutations (each separate, none executed)

Places write (building bootstrap is impossible: a building exists); creating or importing the first parking mailbox; Terraform apply of any declaration above; worker activation; Key Vault creation (paid, cost approval); any booking write.

### Worker prerequisites (ADR-013, ADR-015, ADR-016)

- Dedicated worker identity `placehub-m365-provisioning-development` (exists; no credential, no declarations, no grants; distinct from the web app: VERIFIED_IN_TENANT).
- Dedicated worker certificate and a worker-only dedicated Key Vault: Azure RBAC, `Key Vault Secrets User` for the worker only, public HTTPS endpoint with firewall default Deny and the approved stable egress IPv4; zero data-plane access for the web. Nothing exists yet; the web container has no Key Vault or Azure credential configuration (checked by `CheckKeyVaultBoundary`).
- No reuse of the Azure CLI login, the web certificate or the Terraform delivery identity.
- Four-eyes: enforced and tested locally (approval binding of version and payload digest, worker revalidation); not yet proven in a live worker, so activation stays blocked.
- A real PowerShell runner (pinned `ExchangeOnlineManagement`, clean-room proof) does not exist; the Exchange worker refuses to run without one.

### Exact Terraform changes (proposal only, not applied, not in the active policy)

1. Web app: add the scope `Calendars.ReadWrite = "1ec239c2-d7c9-4623-a91a-a9775856bb36"` to `approved_read_only_scopes` (rename to `approved_scopes`) and to the exact `required_resource_access` of `policy/development.json`; classifier fixtures for the addition; plan expected `UPDATE_ONLY` with one permission added. Consent stays a separate administrator action.
2. Worker app: `required_resource_access` for Microsoft Graph (`Role`, `f1f5e9aa-…`) and, only if the creation model needs PowerShell, Office 365 Exchange Online (`00000002-0000-0ff1-ce00-000000000000`, `Role`, `dc50a0fb-…`); policy `required_resource_access` exact for `azuread_application.m365_provisioning`; public worker certificate registered out-of-band under the same ADR-016 option B (a post-registration plan must show `NO_CHANGE`).
3. Key Vault: `azurerm_key_vault` with `rbac_authorization_enabled = true`, `public_network_access_enabled = true`, `network_acls { default_action = "Deny", ip_rules = [<approved egress IPv4>] }`, one `azurerm_role_assignment` (`Key Vault Secrets User`) for the worker principal only; added to the policy allowlist with exact attributes. Paid resource: cost approval first.
4. Every item passes the existing exact-plan workflow: unknown or destructive plans fail closed, no apply without explicit authorization.

### First safe, approved development end-to-end test procedure

**Stage 0 – needs no new approval (can run now):**
1. Open `https://localhost:3242` (never `127.0.0.1`), sign in, and capture the Dashboard: expect building HomeOffice, its floor, the section `Links`, and the room `Home`; the line "Listen vor Standortfilter" shows what the lists returned and how many direct lookups were needed.
2. Integration & Diagnose → "Diagnose ausführen": record the outcome class (expected `RESOURCE_FOUND` or `INCONSISTENT_DIRECTORY_STATE`; propagation is never asserted).
3. In a Graph PowerShell session with `Place.Read.All`: `pwsh scripts/Invoke-PlaceHub-Requirements.ps1 DiagnosePlacesHierarchy -PlaceId e25ee6c6-86bb-4ce4-b3f5-b1df37f71a1b,de9eccf8-8056-425a-a939-7c496656f038,139637d0-126e-440b-9276-26e0354d6024` (building, the presumed floor, the section) to verify the chain by id; the floor `de9eccf8-…` is only inferred from the section's `parentId`.
4. Open the booking calendar: free/busy of the room `Home` through delegated `getSchedule` (`Calendars.ReadBasic`, already consented). Record the source and time.
5. Negative checks: a user without a PlaceHub role gets 403; a user without a location assignment gets the denial state; `127.0.0.1` fails with the redirect-URI error (by design).
6. Run `Status` and keep `requirements-status.json`/`.md` as evidence.

**Stage 1 – after ADR-006 acceptance (no permission needed):** an administrator creates one development equipment mailbox with the approved name and domain outside PlaceHub. Registration in PlaceHub stays pending verification because no live runner exists, and reservations require an *Active* (worker-verified) parking space. Known limitation: the legacy availability page `/parkplaetze` lists Places workspaces and rooms with a mailbox, not equipment mailboxes; equipment appears only through the parking module once verified.

**Stage 2 – after ADR-007 acceptance, consent and the Terraform declaration:** one real organizer booking against that resource with read-back until Exchange accepts or declines, then cancellation and a negative authorization test.

**Stage 3 – after the worker prerequisites:** enable the Exchange runner for read-only verification first (`Reconcile`), then one approved `ConfigureBookingPolicy`, always with a different approver.

Live-write readiness is claimed only after an authorized write, read-after-write verification and a negative authorization test have succeeded.
