# UI-driven resource administration POC

**Status:** Implemented offline POC; no live Microsoft 365 permission or operation is approved.

## Scope and trust boundaries

The Blazor UI creates typed `DeskPool` and `ParkingResource` administration requests. Role and location checks execute in the application service, never only in the UI. A PlaceHub System Administrator can approve and trigger the offline mock. This app role is not an Exchange or Entra administrator role.

The production-shaped boundary is `web → immutable approved request → isolated worker → Microsoft 365`. The POC registers only `OfflineMockProvisioningWorker`; it has no Graph/Exchange dependency, token, certificate or network client. The supplied PowerShell module is an offline contract demonstration with `SupportsShouldProcess`, fixed operations and parameter validation. It deliberately contains no live administrative command.

## Domain mapping

| PlaceHub concept | Proposed Microsoft representation | POC representation |
|---|---|---|
| Building → Floor → Section | Native Microsoft Places hierarchy | Synthetic stable IDs |
| Desk pool | Workspace beneath a Section; Exchange Room mailbox converted/configured as Workspace, subject to tenant proof | `DeskPool` fixture with workspace mailbox metadata |
| Parking space | Proposed Exchange Equipment mailbox associated with building; Room remains test alternative | Typed `ParkingResource` request |
| Reservation | Exchange calendar/resource processing remains authoritative | Display/mock status only; never local authority |

Desk pools and parking use different operation types and must never share mailbox-type assumptions.

Current Microsoft documentation exposes two relevant paths that must be resolved during test-tenant discovery. The desk-booking guide documents the explicit Exchange sequence `New-Mailbox -Room | Set-Mailbox -Type Workspace`, `Set-CalendarProcessing -EnforceCapacity $true`, followed by `Set-PlaceV3` parent/capacity association. The newer `New-Place -Type Workspace` documentation describes automatic mailbox provisioning and recommends that route over legacy mailbox-first creation. The POC chooses neither for live use: both remain adapter contract candidates until module version, licensing, RBAC behavior, propagation and rollback are proven and ADR-005/015 are approved.

## Workflow and controls

The state model is `Draft → Submitted → AwaitingApproval → Approved → Running → PendingPropagation/Succeeded/Failed/PartiallyConfigured/RequiresReconciliation`; rejection is explicit. Current POC operations require approval. Automatic approval remains disabled until a narrowly defined policy is accepted.

- idempotency keys prevent duplicate submission;
- optimistic versions reject stale edits and approval replay;
- role and location authorization is rechecked at approve and execute time;
- approved requests are immutable;
- only fixed resource, operation and policy values can reach the worker;
- partial outcomes cannot be presented as success and require a future explicit reconcile transition;
- audit metadata contains correlation ID, stable event code, state and version only.

Local workflow persistence is currently an in-memory adapter because this initial slice has no schema migration. SQLite remains the accepted persistence target under ADR-010; durable/restart-safe execution must not be enabled until a reviewed migration, encryption/retention and concurrency implementation exist.

## UI use

Run `dotnet run --project src/PlaceHub.Web` and open the displayed loopback URL. The role selector is a clearly marked synthetic POC harness, not an authentication implementation. Create a request under **Schreibtischgruppen** or **Parkplätze**, then select **PlaceHub Administrator** and use **Provisionierungsaufträge** to approve and execute the mock.

Names containing `TeilFehler` simulate partial configuration; names containing `Abgleich` simulate reconciliation. No route can activate live access.

## Permission and consent matrix

| Use case | Identity | Candidate | Consent/RBAC | Current disposition |
|---|---|---|---|---|
| Sign-in and app role | `placehub-frontend-development` | OIDC authorization code | App-role assignment | Registration exists; real sign-in integration not enabled in this POC |
| Read Places | Web, delegated | `Place.Read.All` | Admin consent | Proposed; do not grant before ADR-004/005 approval |
| Interactive booking | Web, delegated | exact calendar scope, initially evaluate `Calendars.ReadWrite` | Consent plus exact operation proof | Proposed; not configured |
| Administer Places | Provisioning app | application `Place.ReadWrite.All` candidate | Admin consent plus documented Places/Exchange role requirements | Proposed; not configured |
| Exchange management | Provisioning app | `Exchange.ManageAsApp` | Admin consent, service-principal pointer and minimal custom Exchange RBAC | Proposed; not configured |
| Existing mailbox data | Provisioning app, only if needed | Exchange Application RBAC data role | resource scope and positive/negative test | Proposed; not configured |

An API declaration is not effective consent. Application permission alone must not be described as sufficient for Places administration. Mailbox creation has residual organization-wide power because a nonexistent mailbox cannot already match a resource scope. Live automatic creation therefore requires explicit security acceptance of naming/domain/type templates, serialized creation, immediate marking, quarantine and audit. Exchange Administrator is not an approved fallback.

## Safe worker runbook

The first live-test candidate remains a dedicated Windows process/service account with a CSP-backed certificate in its ACL-protected OS store. Before activation: pin PowerShell/Exchange module versions and hashes; prove the custom role entries and exact parameter allowlist read-only; validate approved and denied mailboxes; enforce one create sequence per logical resource; configure timeouts and bounded retries; disable transcripts/dumps; document certificate rotation/revocation; and rehearse partial-failure reconciliation. No Key Vault or paid Azure worker is introduced.

Routine recovery never runs arbitrary operator text. It replays a typed `Reconcile` request against the same logical resource and expected version. Mailbox deletion is excluded; disable must be reversible and separately approved.

## Validation

```powershell
dotnet test PlaceHub.slnx
pwsh -NoProfile -File tests/Test-ProvisioningMock.ps1
pwsh -NoProfile -File tests/Test-Static.ps1
```

Security tests cover role-only submission/approval, location denial, stale approval, duplicate idempotency, immutable approval, parameter injection, partial outcomes and the offline tenant boundary. Live/test-tenant contract tests remain approval-gated.

## Remaining approval gates

1. Accept or reject ADR-004/005/006/007/015 amendments; none are accepted by this POC.
2. Approve exact Graph delegated/application permissions and tenant admin consent.
3. Approve Exchange management roles, role entries, parameters, recipient scope and the residual create scope.
4. Approve tenant licenses and prove Workspace/Places behavior in a test tenant.
5. Approve certificate owner/lifecycle and isolated worker host; keep web/worker credentials separate.
6. Replace the synthetic role selector with Entra authentication, assignment and server-side location administration.
7. Add reviewed SQLite migration and durable queue/lease behavior before real execution.
8. Approve production identities, hosting, monitoring, data protection and cost separately.

ADR-016 is unaffected: no Terraform resource, permission declaration, consent, Azure resource or live apply was added.

## Official evidence reviewed

- [Create a desk pool / desk booking](https://learn.microsoft.com/microsoft-365/places/configure-desk-booking)
- [`New-Place` workspace and hierarchy behavior](https://learn.microsoft.com/microsoft-365/places/powershell/new-place)
- [Microsoft Graph create place and authorization requirements](https://learn.microsoft.com/graph/api/place-post?view=graph-rest-1.0)
- [Exchange Application RBAC](https://learn.microsoft.com/exchange/permissions-exo/application-rbac)
- [Exchange resource mailboxes](https://learn.microsoft.com/exchange/recipients-in-exchange-online/manage-resource-mailboxes)
