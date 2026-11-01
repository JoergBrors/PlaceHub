# Phase 3 request, queue and worker readiness

**Status:** Partial safe preparation. No live worker, durable queue or Microsoft 365 mutation is enabled.

## Implemented without new architecture

- Existing typed resource requests retain version-bound approval, idempotency key, location authorization and allowlisted operations.
- **Meine Aufträge** displays only requests from locations assigned to the current synthetic actor, with summary counters, filtering, correlation reference, next step and chronological safe timeline.
- **Freigaben** remains restricted to the PlaceHub System Administrator application role. That role is not an Exchange, Entra or tenant-administrator role.
- Offline mock execution contains no Graph/Exchange client, credential, certificate or arbitrary PowerShell input.
- Microsoft 365 reads remain separately controlled by the Phase-2 read-only adapters.

The current repository still stores requests in memory and invokes the mock adapter from the web process. Consequently, data is lost on restart, there is no worker heartbeat, and **Wartet auf Worker** describes an approved business request—not a durable queue claim.

## Architectural stop

Proposed ADR-015 governs privileged operations but is not accepted. Proposed ADR-017 now records the missing decisions for SQLite persistence, request/execution state separation, leases, crash recovery, retry/reconciliation and the separate worker process. Until both are approved, PlaceHub must not claim durable processing or isolated execution.

## Prepared Entra configuration

Terraform already contains stable, immutable role IDs for `PlaceHub.OfficeManager`, `PlaceHub.LocationManager` and `PlaceHub.SystemAdministrator`, each limited to user members. The service principal requires assignment. No role assignment resource, credential, effective Graph grant or admin consent is added. Users without one recognized role must be denied when live authentication is later activated; location assignment remains an independent server-side check.

## Permission status

- Delegated candidates: `Place.Read.All`, `Calendars.ReadBasic`, optionally `User.Read` only if evidence requires it.
- Deferred writes: `Place.ReadWrite.All`, `Calendars.ReadWrite`.
- Privileged worker candidates: application `Place.ReadWrite.All` and `Exchange.ManageAsApp` only after exact operation/RBAC evidence.
- Terraform `required_resource_access` remains empty. Declaration, admin consent, Exchange Application RBAC and application role assignments are distinct administrative operations.

## Activation sequence

1. Accept or amend ADR-004/005/006/007/011/015 and ADR-017 as applicable.
2. Approve a non-production tenant and confidential-web credential strategy.
3. Review the exact Terraform permission-policy change; apply through ADR-016 only after approval.
4. Assign users/groups to one PlaceHub app role and verify positive/negative role claims.
5. Implement and validate SQLite migrations and transactional lease fixtures after ADR-017 acceptance.
6. Start the mock worker as a separate process and prove restart, expiry, duplicate claim and reconciliation behavior.
7. Separately approve the worker certificate, Exchange Application RBAC, residual mailbox-create privilege, command allowlists and runtime.
8. Run authorized test-tenant positive and negative tests before any live activation.

## Official evidence

- [ASP.NET Core confidential OIDC](https://learn.microsoft.com/aspnet/core/security/authentication/configure-oidc-web-authentication?view=aspnetcore-10.0)
- [Blazor OIDC application roles](https://learn.microsoft.com/aspnet/core/blazor/security/blazor-web-app-with-oidc?view=aspnetcore-10.0#application-roles-for-apps-registered-with-microsoft-entra-me-id)
- [Microsoft Graph Places](https://learn.microsoft.com/graph/api/resources/places-api-overview?view=graph-rest-1.0)
- [Microsoft Graph getSchedule](https://learn.microsoft.com/graph/api/calendar-getschedule?view=graph-rest-1.0)
- [Exchange Application RBAC](https://learn.microsoft.com/exchange/permissions-exo/application-rbac)
- [Microsoft Places New-Place](https://learn.microsoft.com/microsoft-365/places/powershell/new-place)
