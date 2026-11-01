# Exchange Online parking-resource provisioning architecture

**Status:** Draft for architecture, security, Microsoft 365 and cost approval. No application, certificate, Key Vault, permission, role, scope or mailbox is authorized.

**Date:** 2026-10-31

## A. Confirmed facts and assumptions

- `placehub-m365-provisioning-development` is a single-tenant daemon application with a dedicated service principal, certificate-based client authentication and no redirect URI or interactive flow.
- It is distinct from the interactive PlaceHub app, its runtime identity and the accepted ADR-016 Terraform delivery identity. None may impersonate or own another by default.
- Exchange Online PowerShell (ExchangeOnlineManagement) is the supported management interface for Equipment Mailbox creation and booking-policy administration. EWS and EWS Managed API are prohibited.
- Microsoft Graph remains the interface for supported availability and ordinary reservation operations. Provisioning PowerShell is never used for routine booking.
- The accepted initial PoC is local Docker, but the privileged worker is outside the web container. A hardened local Windows process is the first proof target; its exact service account/module configuration remains an ADR-015 gate.
- Commands and effective RBAC entries vary by tenant and module version. Exact roles, parameters and scoping behavior must be discovered read-only and then proven in a separately approved test tenant.
- New mailbox creation presents a fundamental scope limitation: the target object does not exist before `New-Mailbox`, so a recipient filter or group membership cannot reliably constrain creation to the future object. No claim of complete resource-scoped creation is made.

## B. Technical feasibility

The design is technically feasible on an approved PowerShell 7 worker. ExchangeOnlineManagement supports certificate-based app-only connection through:

```text
Connect-ExchangeOnline -AppId <app-id> -Certificate <X509Certificate2> -Organization <primary-onmicrosoft-domain> -ShowBanner:$false
```

`-Certificate` is cross-platform and is appropriate for a certificate fetched remotely. `-CertificateThumbprint` is Windows-only and requires a certificate-store installation, so it is not the portable worker contract. Module 3.10.0 and later requires PowerShell 7.6/.NET 10; pin and test an exact supported module version rather than floating `latest`.

Microsoft's app-only guidance states that CNG certificates are unsupported for this Exchange authentication path. Use an RSA certificate whose private key is generated with a legacy CSP provider. For Windows enrollment the proposed key specification is `AT_KEYEXCHANGE`, with a reviewed CSP such as `Microsoft Enhanced RSA and AES Cryptographic Provider`. A local certificate-store key may remain non-exportable at runtime; exportability is needed only if the approved enrollment/transfer path produces a PFX or a future Key Vault worker retrieves it. The test gate inspects the provider and completes a live test-tenant login.

The Entra application receives only the Office 365 Exchange Online application role `Exchange.ManageAsApp`, resource application ID `00000002-0000-0ff1-ce00-000000000000`, role ID `dc50a0fb-09a3-484d-be87-e023b12c6440`, after explicit admin-consent approval. It receives no Microsoft Graph permission unless a separate Graph use case is approved. Exchange RBAC still determines permitted cmdlets/parameters and recipient scope.

## C. Identity and certificate architecture

| Component | Responsibility | Prohibited access |
|---|---|---|
| Office Manager | Requests a business operation after application-role and location authorization. | Exchange token, certificate, Key Vault, arbitrary PowerShell. |
| PlaceHub web application | Validates, normalizes and records a provisioning request; shows status. | Exchange administrative credential/session; direct privileged command execution. |
| Provisioning worker runtime identity | Reads exactly the approved certificate secret and executes queued, typed operations. | Key Vault administration, certificate issuance, Terraform state, other environments. |
| `placehub-m365-provisioning-development` | Authenticates the worker to Exchange Online. | Interactive login, web authentication, Terraform, broad Graph grants. |
| Certificate operator group | Enrolls, uploads, rotates and revokes certificates under change control. | Routine provisioning execution unless separately assigned. |
| Exchange security administrator | Grants consent and custom Exchange RBAC after approval. | Runtime private-key access. |
| Terraform identity | May eventually create approved Azure shell resources under ADR-016. | Certificate contents, admin consent, Exchange RBAC or mailbox operations by default. |

Certificate profile proposed for test validation:

- X.509 v3, RSA 2048 bits or stronger according to organizational policy; SHA-256 signature; client-authentication use only.
- CSP-backed private key with `AT_KEYEXCHANGE`; not CNG/KSP, EC or HSM-only.
- Subject/SAN contains no secret and identifies application/environment; distinct key pair per environment.
- Short, policy-approved lifetime (target at most 12 months), explicit `notBefore`/`notAfter`, and certificate thumbprint recorded as non-secret inventory metadata.
- Local Windows-store private key non-exportable where enrollment/rotation permits; exportable only for an approved PFX transfer or future Key-Vault-to-`X509Certificate2` path.
- Public `.cer` uploaded to the Entra application. PFX/private key exists only in the approved certificate store/Key Vault and worker memory.

The detailed rotation and emergency procedure is in [Exchange certificate lifecycle runbook](exchange-certificate-lifecycle-runbook.md).

## D. Key Vault access and lifecycle design

If hosting and cost are approved, use one Azure RBAC-mode Standard Key Vault per application environment. Enable soft delete and purge protection with the approved retention period. Development and production use different subscriptions/resource groups where required, vaults, runtime identities, certificates, role assignments and audit destinations.

The Exchange module cannot sign through a non-exportable Key Vault key for this flow. The certificate must be created/imported with an exportable RSA private key; Key Vault stores the complete PFX as the certificate's backing secret. The worker uses managed identity to retrieve the current, explicitly selected version and creates an ephemeral `X509Certificate2` with private-key flags that avoid persistent key storage. It passes that object to `Connect-ExchangeOnline -Certificate`, disposes it after disconnect and never writes a PFX to disk.

| Principal | Scope | Proposed role/capability |
|---|---|---|
| Provisioning runtime identity | Development vault only | `Key Vault Secrets User` (`4633458b-17de-408a-b874-0445c86b69e6`) or a reviewed narrower custom role; read the secret portion containing the private key. No set/delete/purge/RBAC. |
| Certificate operators | Environment vault | Certificate lifecycle role sufficient to import/create versions; separate secret-read access only when operationally required and approved. |
| Security recovery operators | Environment vault | Time-bound recovery/purge duties separated from routine certificate operation. |
| Interactive users | None | No private-key or secret read. |
| Terraform deployment identity | Control plane only if approved | No data-plane certificate/secret read and no ability to self-assign it. |

`Key Vault Certificate User` can also read the full certificate including key/secret portion, but the selected built-in role must be verified against the exact SDK operation. Prefer the smallest role that allows only the required backing-secret `get`. Avoid `Key Vault Administrator`, `Secrets Officer`, subscription-wide assignments and legacy access policies. Control-plane Contributor must not be able to grant itself data-plane access; RBAC assignment authority stays separate.

Loading the PFX into memory means a compromised worker, debugger, crash dump, process-dump right, malicious module or same-host administrator can extract the private key. Mitigations are a dedicated short-lived worker process/container, no interactive login, minimal administrators, disabled dumps and PowerShell transcripts, signed/pinned dependencies, constrained egress, one operation at a time, immediate object disposal, rapid certificate revocation, and detection of unexpected Key Vault reads or service-principal sign-ins. Memory cannot be proven perfectly erased by managed code; this residual risk requires explicit security acceptance.

Key Vault is a metered paid service and diagnostics can add ingestion/storage charges. It is excluded from the zero-new-paid-resource development profile until cost approval. The secure development-only alternative is an OS certificate store on a dedicated test workstation/worker: CSP-backed non-exportable-at-rest key ACL limited to its service account, `Connect-ExchangeOnline -CertificateThumbprint` on Windows or an in-memory certificate object after protected retrieval. No PFX/password in repository, `.env`, CI variables, artifacts or ordinary filesystem. This alternative is for the approved test tenant only and requires manual rotation/audit; it is not a production design.

## E. Exchange command and RBAC matrix

| Adapter operation | Fixed commands | Candidate minimum role source | Scope/limitation |
|---|---|---|---|
| `DiscoverResourceMailbox` | `Get-EXOMailbox` with fixed identity/filter and property allowlist; `Get-CalendarProcessing` | Read-only recipient/configuration role entries, discovered in tenant | Existing recipients can be filtered/scoped; prevent unrestricted enumeration in adapter output. |
| `CreateParkingResource` | `New-Mailbox -Equipment` with allowlisted `Name`, `Alias`, `DisplayName`, `PrimarySmtpAddress` only | Custom role derived from the verified role containing these exact entries (often `Mail Recipients`, but not assumed) | A resource scope cannot reliably restrict a mailbox that does not exist. Creation may remain organization-scope administrative power. Explicit security decision or human creation required. |
| `UpdateParkingResource` | `Set-Mailbox` with exact identity and separately approved property subset | Custom recipient role with parameter allowlist | Existing-mailbox recipient write scope must match the approved development marker. Never expose forwarding, delegation, litigation or type conversion parameters. |
| `ConfigureBookingPolicy` | `Get-CalendarProcessing`; `Set-CalendarProcessing` with an approved policy template | Custom role entries discovered for exact parameters | Scope existing resource mailbox. Reject `-IgnoreDefaultScope`; no arbitrary delegates/response text. |
| `DisableParkingResource` | Prefer reversible `Set-Mailbox` changes defined by approved lifecycle; no `Remove-Mailbox` | Same minimal custom role | Exact disable semantics remain an ADR-006 decision; deletion is excluded. |
| `VerifyProvisioningState` | Bounded `Get-EXOMailbox` plus `Get-CalendarProcessing` | Read-only entries | Poll with timeout/backoff because directory/mailbox visibility may be asynchronous. |
| Session lifecycle | `Connect-ExchangeOnline`, `Disconnect-ExchangeOnline -Confirm:$false` | `Exchange.ManageAsApp` plus assigned Exchange RBAC | Always disconnect in `finally`; connection itself does not authorize commands. |

Before defining a custom role, an authorized administrator must run read-only discovery for every command and parameter, for example `Get-ManagementRole -Cmdlet ... -CmdletParameters ...` and `Get-ManagementRoleEntry -Identity *\<Cmdlet> -Parameters ...`. Build a child role from the verified parent and remove every unused role entry/parameter. Capture sanitized role definitions for review. Do not infer production roles from documentation examples.

Exchange Application RBAC data-access roles such as `Application Calendars.Read` scope Graph app-only mailbox data. They do not by themselves authorize Exchange management cmdlets. Conversely, a custom management role for mailbox provisioning does not authorize Graph calendar data. Unscoped Entra grants and Exchange assignments are additive; remove conflicting unscoped grants before claiming scope enforcement.

### Mailbox-creation security decision

The preferred least-privilege design is two-step:

1. A human Exchange administrator creates the Equipment Mailbox and applies the approved development scope marker.
2. The application worker configures and verifies only already-scoped mailboxes.

Fully automated creation is permitted only if security explicitly accepts residual organization-wide `New-Mailbox` capability, the custom role exposes no broader create/update parameters, the adapter enforces an approved SMTP domain/naming/location template, requests require approval, execution is serialized, and post-create marking/configuration is immediately verified. A failure before scoping is quarantined for manual reconciliation; it is never silently retried into duplicate creation.

## F. .NET 10 provisioning adapter

The application-facing contract is implementation-neutral and asynchronous:

```text
DiscoverResourceMailbox(query, authorizationContext, correlationId)
CreateParkingResource(specification, idempotencyKey, authorizationContext, correlationId)
UpdateParkingResource(resourceId, expectedVersion, patch, authorizationContext, correlationId)
ConfigureBookingPolicy(resourceId, policyTemplateId, authorizationContext, correlationId)
DisableParkingResource(resourceId, reason, authorizationContext, correlationId)
VerifyProvisioningState(operationId, correlationId)
```

Return typed states `Requested`, `Authorized`, `Running`, `PendingPropagation`, `Succeeded`, `Failed`, `PartiallyConfigured`, `RequiresReconciliation` and `Rejected`; never return raw PowerShell objects or errors.

The web process writes an immutable, authorized request. A separate worker maps its type to a fixed command template. No command name, script text, expression, property name or free-form filter supplied by a user reaches PowerShell. Validate canonical mailbox identity, approved SMTP suffix, normalized alias/name lengths, location ownership, policy-template ID and expected state before execution.

Run ExchangeOnlineManagement in a dedicated child process or isolated worker with an exact module hash/version and a fixed `-CommandName` allowlist where supported. Limit concurrency to one creation/configuration sequence per mailbox and a small tenant-wide maximum. Apply per-command and whole-operation deadlines; cancellation stops further mutation but still performs verification and disconnect. Never kill an operation and assume rollback.

Use an idempotency record keyed by environment, operation kind and business resource ID. Before create, query exact alias/SMTP/external ID; an identical existing mailbox becomes verification, while a collision is `Rejected`. After every mutation, perform bounded read-after-write polling. Partial creation followed by configuration failure becomes `PartiallyConfigured`, blocks a new create and schedules reconciliation. Compensation is an explicitly defined reversible change, never mailbox deletion.

`Disconnect-ExchangeOnline -Confirm:$false` and certificate disposal run in `finally`. Start a clean process after authentication/session corruption. Log only correlation ID, operation type, approved logical resource reference, state, attempt and stable error category. Exclude certificate bytes/passwords/thumbprints where policy treats them as sensitive, tokens, Key Vault secret IDs/versions, raw command lines, PowerShell streams, mailbox/calendar contents and exception text.

## G. Hosting, threat and cost assessment

### Hosting assessment

| Option | Assessment |
|---|---|
| App Service F1 web process | Rejected for privileged execution: shared web lifecycle, quota/process constraints, dependency installation and insufficient separation from the interactive app. |
| Dedicated Azure worker | Technically suitable if the chosen service supports pinned PowerShell/.NET, managed identity, outbound Exchange/Key Vault access, process isolation and timeouts. It and Key Vault can incur cost and require ADR-013 approval. |
| Dedicated on-premises Windows worker | Suitable development/test candidate with CSP certificate store, controlled service account, egress and patching; uses existing infrastructure but transfers availability, backup and host-admin risk to operations. |
| Operator-run controlled workstation | Acceptable only for initial test-tenant proof and manual provisioning; not unattended production. |

Stop implementation until a host passes a clean-room proof using the selected OS, PowerShell 7, exact ExchangeOnlineManagement version, CSP certificate source, `X509Certificate2` import flags, Key Vault SDK if applicable, connection, all allowlisted commands and teardown. The current no-paid-resource posture therefore selects only the controlled local/on-premises test-worker option; Azure Key Vault/dedicated Azure compute require separate cost approval.

### Threat model

| Threat | Primary controls | Residual risk |
|---|---|---|
| Private-key theft from Key Vault or memory | Dedicated identity/vault, read-only secret role, isolation, no disk, dumps/transcripts disabled, alerts, short lifetime and revocation | Host administrator or process compromise can extract exportable key. |
| Privilege escalation through arbitrary PowerShell | Typed interface, fixed command/parameter allowlist, no expressions, pinned module, custom Exchange role | Module/service defects and overly broad role entries. |
| Cross-location/environment provisioning | App role plus location authorization, environment-bound worker/identity/certificate/vault, naming/domain rules | Creation scope cannot bind a nonexistent object. |
| Duplicate or orphaned mailbox | Idempotency key, exact preflight, serialized create, read-after-write, reconciliation | Exchange propagation can remain ambiguous temporarily. |
| Log/telemetry disclosure | Allowlisted structured audit fields; suppress raw streams/arguments/errors | Platform diagnostics may still contain metadata. |
| Certificate expiry/rotation outage | 60/30/14/7-day alerts, overlapping public credentials, pre/post tests, rollback | Manual process or tenant outage can delay rotation. |
| Compromised Terraform identity | No Key Vault data role, Exchange role, consent or certificate ownership | Control-plane Contributor could affect approved Azure resources; keep role scope narrow. |
| Destructive mailbox action | No delete command, reversible disable, approval and verification | Misconfiguration can still disrupt bookings. |

## H. ADR impact and approval gates

No accepted-decision conflict was found. Amended ADR-016 permits in-boundary create/update but does not approve Key Vault, an Exchange worker, consent, Exchange RBAC or certificate access. Terraform may later describe an approved Key Vault/worker shell, but must not read certificate contents, execute Exchange cmdlets or reuse the provisioning identity. Deletion/access removal remains destructive, and plan/state must never contain PFX data.

ADR-004, ADR-006, ADR-007, ADR-009, ADR-012, ADR-013 and ADR-015 remain proposed. Their refinements are supporting design, not approval.

Required approvals before implementation:

1. Equipment Mailbox model and exact enabled/disabled lifecycle.
2. Human-created versus automated mailbox creation and acceptance of any organization-wide residual create privilege.
3. Exact ExchangeOnlineManagement and PowerShell versions, commands, parameters, parent/custom roles and resource-scope filter proven in the test tenant.
4. `Exchange.ManageAsApp` application permission and admin consent.
5. Worker host, network, patching, administrator boundary, runtime identity and operational cost.
6. CSP-backed certificate profile, issuer, lifetime, owners, non-exportable local-store path, optional exportable transfer/Key Vault path and in-memory extraction risk.
7. Key Vault cost, Azure RBAC assignments, purge retention, monitoring destination and environment separation—or approval of local test store only.
8. Request approval, audit retention, incident response, certificate revocation and reconciliation procedures.
9. Any Terraform management of Azure/Entra objects under ADR-016's separate gate.
10. Separate production identities, vault, certificates, scopes, threat review and change authorization.

## I. Test plan and implementation backlog

All integration tests use synthetic resources in a separately approved test tenant.

### Test matrix

- Static: no EWS package/reference, client secret, PFX/private key, arbitrary script input, mailbox delete or broad built-in administrator assignment.
- Certificate: RSA/CSP/`AT_KEYEXCHANGE`, private key present, expiry and chain policy, exact public-key match in Entra, non-CNG assertion.
- Authentication: successful app-only login; expired/not-yet-valid/revoked/unregistered certificate; missing `Exchange.ManageAsApp`; old/new overlap and rollback.
- Key Vault: approved runtime can get only the selected certificate secret; access denied for web, user, Terraform and other environment; unavailable/disabled version; no persistent file; memory/dump controls reviewed.
- Exchange RBAC: every command/parameter positive case; forbidden command/parameter; allowed existing mailbox; unmarked, other-location, user and production mailbox denial; enumerate effective assignments.
- Workflow: successful equipment creation (only if approved), duplicate/collision, propagation timeout, policy failure after creation, retry/reconciliation, cancellation, disconnect failure and worker restart.
- Security: cross-tenant/environment/location denial; injected PowerShell/filter/identity input; excessive concurrency; logs contain none of the synthetic token/PFX/password/private-key/raw-output canaries.

### Staged backlog

1. **Tenant discovery package:** pin candidate module/runtime; record supported OS; enumerate cmdlet/parameter role entries and scope filters read-only. Acceptance: reviewed evidence without tenant secrets.
2. **Certificate proof:** enroll CSP RSA certificate, upload public key manually under change control, prove `X509Certificate2` connection and revoke it. Acceptance: CNG rejected; no private material persisted or logged.
3. **RBAC proof:** create test-only service-principal pointer, custom role and scope after approval; run positive/negative matrix. Acceptance: denied targets and commands fail; creation residual documented.
4. **Host proof:** validate isolated worker, identity, dependency pinning, network, timeout/cancellation, session cleanup, dumps/logging and patch process. Acceptance: F1 is not used.
5. **Credential store proof:** choose local test store or approved Key Vault; implement version selection, memory-only import, rotation and access-denial tests. Acceptance: only worker reads private material.
6. **Adapter implementation:** typed contracts, validators, allowlisted command mapper, process boundary and safe result translation. Acceptance: unit/fuzz tests prevent command injection.
7. **State machine and audit:** idempotency, authorization snapshot, read-after-write, partial failure and reconciliation. Acceptance: duplicate create never occurs in synthetic concurrency tests.
8. **Test-tenant integration:** exercise the complete matrix with synthetic mailboxes and approved teardown. Acceptance: evidence reviewed by Exchange/security owners.
9. **Operational readiness:** rotate certificate, simulate revocation/outage, reconcile orphan and run incident procedure. Acceptance: signed runbooks and named owners.
10. **Production gate:** repeat permission/scope/cost/threat review with separate production resources. Acceptance: explicit approval; no development credential or consent reused.

## Official references

- [App-only authentication for Exchange Online PowerShell](https://learn.microsoft.com/powershell/exchange/app-only-auth-powershell-v2)
- [`Connect-ExchangeOnline`](https://learn.microsoft.com/powershell/module/exchangepowershell/connect-exchangeonline)
- [Exchange Online PowerShell module support](https://learn.microsoft.com/powershell/exchange/exchange-online-powershell-v2)
- [Manage equipment mailboxes](https://learn.microsoft.com/exchange/recipients/equipment-mailboxes)
- [`Get-EXOMailbox`](https://learn.microsoft.com/powershell/module/exchangepowershell/get-exomailbox)
- [`Get-CalendarProcessing`](https://learn.microsoft.com/powershell/module/exchangepowershell/get-calendarprocessing)
- [`Set-CalendarProcessing`](https://learn.microsoft.com/powershell/module/exchangepowershell/set-calendarprocessing)
- [Find Exchange cmdlet permissions](https://learn.microsoft.com/powershell/exchange/find-exchange-cmdlet-permissions)
- [Exchange Application RBAC](https://learn.microsoft.com/exchange/permissions-exo/application-rbac)
- [Key Vault certificates and exportability](https://learn.microsoft.com/azure/key-vault/certificates/about-certificates)
- [Export Key Vault certificates](https://learn.microsoft.com/azure/key-vault/certificates/how-to-export-certificate)
- [Key Vault Azure RBAC guide](https://learn.microsoft.com/azure/key-vault/general/rbac-guide)
- [Key Vault soft delete and purge protection](https://learn.microsoft.com/azure/key-vault/general/soft-delete-overview)

## Implementation status (2026-11-01)

Implemented and tested offline, disabled by default (`ExchangeProvisioningOptions.Enabled=false`): typed `ExchangeSpec`, `ExchangeCommandPlanner` with the fixed allowlist below, `GuardedExchangeRunner`, `ExchangeProvisioningWorker`, and the PlaceHub-owned parking metadata module (`ParkingService`). Cmdlets: `Get-EXOMailbox` (Identity, Properties), `Get-CalendarProcessing` (Identity), `New-Mailbox` (Equipment or Room, Name, Alias, DisplayName, PrimarySmtpAddress), `Set-Mailbox` (Identity, DisplayName), `Set-CalendarProcessing` (Identity, AutomateProcessing, AllowConflicts, BookingWindowInDays, MaximumDurationInMinutes, AllowRecurringMeetings). No `Remove-*`, no delegation, forwarding or type-conversion parameters; values are validated against strict patterns and rejected if they contain shell metacharacters. The two policy templates `standard` and `restricted` are **proposals** built from those documented parameters and need Project Owner approval.

Gates (all closed): worker activation, `MailboxCreationApproved` (organization-wide `New-Mailbox` residual risk), `ApprovedMailboxType` (Equipment versus Room, ADR-006 undecided: creation is refused while null), approved SMTP domains and name prefix, and a real runner. There is **no real PowerShell runner** (`UnavailableExchangeCommandRunner`); it requires the clean-room proof, pinned `ExchangeOnlineManagement` version and certificate source described above. Disable semantics are undecided (`DISABLE_SEMANTICS_NOT_DECIDED`); deletion does not exist. The web process references none of these worker types (`WebBoundaryTests`). Live Exchange behavior is NOT_TESTED.

