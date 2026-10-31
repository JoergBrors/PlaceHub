# ADR consistency audit and local-first harmonization

**Audit date:** 2026-10-31  
**Authority:** Project Owner confirmed local-first initial-PoC direction  
**Scope:** Documentation only; no implementation or operational authorization

## Classification model

- **Confirmed:** explicitly approved repository architecture.
- **Proposed:** material choice remains open; not an implementation mandate.
- **Unresolved:** evidence, ownership or operational choice is missing.
- **Externally verified:** material technical statement checked against official vendor documentation.
- **Superseded:** an older recommendation is retained only as history or replaced by the confirmed direction.

## Executive finding

No conflict exists with accepted ADR-016 because it governs Terraform delivery, not application hosting. The former App Service F1 initial-PoC recommendation was inconsistent with the later Project Owner direction and is superseded by local Docker Compose. The accepted initial baseline is one .NET 10 server-side Blazor modular monolith in a portable Linux image, SQLite with synthetic disposable data, offline Graph/Exchange mocks, safe local diagnostics and zero incremental Azure resources.

Acceptance does not grant tenant permission, consent, Exchange administration, application implementation, paid service or production deployment. ADR-004–008, 011 and 015 remain proposed.

## ADR-by-ADR compliance matrix

| ADR | Before → after | Classification | Consistency and exact harmonization | Outstanding decision / operational gate |
|---|---|---|---|---|
| 001 Overall architecture | Proposed → **Accepted** | Confirmed | Modular monolith preserved; local Linux image is deployment packaging, not a topology change. | Production scale/topology or material module-boundary change needs amendment. |
| 002 Frontend | Proposed → **Accepted** | Confirmed | Server-side Blazor and server-side tokens retained; exact fixed HTTPS localhost callback added. | Entra callback mutation, consent and any future SPA/API split. |
| 003 Backend | Proposed → **Accepted** | Confirmed | Pragmatic Clean Architecture accepted; Domain/Application are cloud-independent and integrations use ports/adapters. | Concrete project layout is implementation detail; architecture tests required. |
| 004 Graph integration | Proposed → **Proposed** | Proposed + externally verified | Graph remains for supported Places/calendar operations; ExchangeOnlineManagement for administration; EWS prohibited; mocks default. | Exact APIs, immutable permission IDs, tenant capability/licensing and consent. |
| 005 Places hierarchy | Proposed → **Proposed** | Proposed + unresolved | Microsoft Places remains authoritative; mock data cannot become a competing hierarchy. | Desk Pool/Workspace mapping, relationships and licensing require current test-tenant evidence. |
| 006 Parking mailboxes | Proposed → **Proposed** | Proposed + unresolved | Equipment Mailbox remains preferred; Room comparison retained; no automatic org-wide `New-Mailbox` grant. | Mailbox type, creation-scope solution, booking policy and lifecycle. |
| 007 Reservations | Proposed → **Proposed** | Proposed | Exchange remains booking authority; delegated organizer flow preferred; async states required in mocks. | Exact Graph booking/cancellation behavior, permissions and reconciliation proof. |
| 008 Visitors | Proposed → **Proposed** | Proposed + unresolved | Initial local data is synthetic/disposable only; real visitor data prohibited. | MVP inclusion, lawful basis, minimization, retention, export/delete and privacy ownership. |
| 009 Authentication | Proposed → **Accepted** | Confirmed | One confidential web registration for monolith; no local Managed Identity; separate provisioning identity; role plus location checks. | Exact callbacks, app-role assignments, Graph consent and Exchange authorization. |
| 010 Persistence | Proposed → **Accepted** | Confirmed, PoC scope | SQLite named volume accepted only for one-instance synthetic disposable PoC data; no booking authority. | Production SQL Server/PostgreSQL, real-data controls, migration, backup/RTO/RPO require amendment. |
| 011 Sync/cache | Proposed → **Proposed** | Proposed + unresolved | Mocks must be visibly non-live; no authoritative Places/booking cache. | TTL, invalidation, staleness, rate limits and reconciliation. |
| 012 Resilience/observability | Proposed → **Accepted** | Confirmed | Safe structured local logs, redaction/correlation and no paid Azure telemetry accepted; provisioning state/reconciliation boundary retained. | Production SLOs, telemetry destination/retention and on-call ownership. |
| 013 Hosting | Proposed → **Accepted** | Confirmed; F1 recommendation superseded | Local Docker Compose is initial host with zero incremental Azure cost. App Service custom container is future funded amendment candidate only. | Docker host assumptions; any cloud host, registry, network, identity, secrets, monitoring and cost. |
| 014 Testing | Proposed → **Accepted** | Confirmed | Container, SQLite, mocks, security/secret canary and separate test-tenant proof strategy accepted. | Live tenant tests require per-operation authorization and synthetic fixtures. |
| 015 Privileged operations | Proposed → **Proposed** | Proposed + externally verified + unresolved | Separate worker, CBA, no client secret/EWS, mock by default. Windows store may use non-exportable CSP key; future Key Vault path is distinct. | Worker host/service account, module version, Exchange RBAC, mailbox create scope, certificate enrollment and consent. |
| 016 Terraform delivery | Accepted → **Accepted, subsequently amended** | Confirmed | OIDC/exact saved-plan/remote-state foundations remain; create/update is normal in-boundary automation, while delete/replacement/access removal requires exact-plan approval. | Protected destructive-plan retention, semantic policy, Entra ownership and production gates remain. |

## Contradictions resolved

1. **F1 versus local hosting:** F1 is no longer the initial PoC. App Service remains a future custom-container candidate only.
2. **Free tier versus zero incremental cost:** Azure free tiers are not used. Existing ADR-016 Blob charges are explicitly separate.
3. **Local Managed Identity:** removed. Local web uses approved confidential OIDC registration only when live sign-in is enabled; runtime identity is abstracted.
4. **Certificate exportability:** local Windows store runtime key can be non-exportable. Exportability applies only to approved PFX transfer or future Key Vault object retrieval.
5. **Key Vault timing:** future paid option, not initial PoC procedure.
6. **SQLite portability:** volume/file is local disposable state, not an App Service migration artifact.
7. **Privileged web execution:** Exchange administration remains outside the web process/container and mocked by default.
8. **Mocks versus authoritative Microsoft 365 data:** fixtures must be explicitly non-live; Exchange and Places remain authoritative.
9. **ADR status text:** accepted decisions now carry approval metadata; unresolved ADRs remain proposed.

## Project-wide invariant result

| Invariant | Result |
|---|---|
| No EWS/EWS Managed API | Satisfied; explicit prohibition. |
| No Exchange administration from web | Satisfied; separate worker/mock boundary. |
| No Terraform identity reuse | Satisfied. |
| No privileged Exchange client secret | Satisfied; certificate only. |
| No Azure runtime/resource required by initial PoC | Satisfied in architecture; no infrastructure implementation exists. |
| No initial Managed Identity/Key Vault | Satisfied. |
| No real sensitive records in SQLite | Satisfied; synthetic/disposable only. |
| Exchange remains booking authority | Satisfied. |
| Microsoft Places hierarchy not duplicated | Satisfied; mock distinction required. |
| No undocumented Graph application permission | Satisfied; candidates remain documented/ungranted. |
| No automatic org-wide `New-Mailbox` | Satisfied; unresolved gate. |
| No implicit production host | Satisfied. |
| ADR statuses match index | Enforced by static test. |
| No obsolete F1 recommendation | Satisfied; only historical/superseded or explicit rejection references remain. |

## External technical evidence

- Microsoft documents .NET 10 SDK/runtime container builds and the non-root `app` user in modern .NET images.
- Microsoft documents SQLite migration/type/locking limitations, including abandoned `__EFMigrationsLock` recovery concerns.
- Microsoft documents App Service custom-container port/persistence behavior and the retirement of its legacy Docker Compose feature; local Compose is not claimed to deploy unchanged.
- Microsoft documents ExchangeOnlineManagement app-only certificate authentication, Windows-only thumbprint use and the CNG restriction for the described CBA setup.
- Microsoft Graph permission/Places operation details remain use-case-specific gates in ADR-004/005 rather than being inferred from planned features.

References are maintained in the relevant architecture documents and ADRs.

## Remaining approval gates

- Exact Docker/Compose versions, local licensing, supported developer host and resource limits.
- Exact localhost HTTPS port/callbacks and any Entra change.
- Image base/digest policy, SBOM/signing and vulnerability threshold.
- Visitor feature/data protection scope.
- Graph operations/permissions/licensing and every live tenant call.
- Exchange mailbox type, RBAC/custom scope, creation model, worker/service account and certificate enrollment.
- Application delivery workflow, artifact integrity and rollback; it is not implied by ADR-016.
- Any future Azure resource, paid service, managed identity, Key Vault, registry, database, monitoring or production deployment.
- Local Docker/hardware/operator and Microsoft 365 test-tenant licensing costs, which are not Azure resource charges.

## Next-phase recommendation

After the remaining implementation prerequisites for accepted ADRs are reviewed, authorize a separate task to create only the solution skeleton, architecture tests, secure multi-stage web image, hardened Compose file, SQLite migration/seed tooling and offline mocks. Keep live Entra/Graph/Exchange and all Azure provisioning out of that phase.

