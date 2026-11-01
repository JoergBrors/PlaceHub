# ADR-007: Parking Reservations and Consistency

- **Status:** Accepted for read-only availability; booking writes remain proposed
- **Priority:** P0
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Approval date:** 2026-11-01
- **Decision authority:** Project Owner approval
- **Governance:** getSchedule availability accepted; create/cancel semantics remain gated

## Context
Zwischen Verfügbarkeitsabfrage und Buchung können konkurrierende Anforderungen entstehen.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Parking Reservations and Consistency** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Proposed Decision
Verfügbarkeit abfragen, regulären Ressourcen-Buchungsprozess auslösen, Ergebnis der Exchange-Verarbeitung verfolgen; Status Pending/Accepted/Declined/Unknown unterscheiden. Keine lokale verbindliche Buchungswahrheit.

## Alternatives Considered
Lokale Sperren (lösen externe Outlook-Buchungen nicht); eigene DB-Transaktionen (konkurrierende Wahrheit); Exchange-Verarbeitung (bevorzugt).

## Rationale
Weniger Konflikte zwischen PlaceHub und Outlook/Exchange.

## Consequences and Trade-offs
Asynchrone Statusklärung, Korrelation, Idempotenz und Kompensation nötig.

## Security and Privacy Implications
Reservierungs- und Stornierungsrechte, personenbezogene Kalenderdaten und Veranstalteridentität schützen.

## Dependencies
ADR-006, ADR-009, ADR-011, ADR-012.

## Validation / Proof of Concept
Zwei konkurrierende Buchungen, Timeout nach Submit, Storno und Fremdbuchung testen.

## Proposed token-flow refinement (not approved)
Bevorzugt erstellt der angemeldete Veranstalter mit delegiertem `Calendars.ReadWrite` eine reguläre Einladung an das Ressourcenpostfach. App-only Kalender-Schreibzugriff ist nur ein separat genehmigter Fallback mit nachgewiesenem Exchange-Mailbox-Scope.

Lokale Mocks müssen Pending/Accepted/Declined/Unknown und verzögerte beziehungsweise widersprüchliche Antworten simulieren. Sie sind nie Buchungsautorität und müssen in UI, Daten und Logs eindeutig von Live-Exchange-Ergebnissen unterscheidbar sein.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Accepted Phase-2 availability amendment

Delegated Microsoft Graph v1.0 `getSchedule` with least-privileged `Calendars.ReadBasic` is the proposed read-only availability boundary. PlaceHub supplies only explicitly authorized resource mailbox addresses and a bounded time interval/time zone, maps free/busy/unknown without appointment subjects and never interprets a free result as a reservation. Missing permission, mailbox, tenant capability, timeout or ambiguous state stays explicit and never falls back silently to mock data.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- `Calendars.ReadWrite`, booking/cancellation operations and test-tenant consent remain separate gates.

## Verification of the booking implementation and consent request (PROPOSED, 2026-11-01 – not a decision)

**Status: PROPOSED – not Accepted.** The implementation exists behind two closed gates (`PlaceHub:Booking:WritesEnabled`, `PlaceHub:Booking:DelegatedWriteScopeApproved`, both false) and is verified with synthetic responses only. Live Exchange behavior is NOT_TESTED.

### Contract check against Microsoft Learn (Graph v1.0)

| Operation | Implemented | Documented |
|---|---|---|
| Create | `POST /me/events`, resource attendee (`type: resource`), `transactionId` | delegated `Calendars.ReadWrite` (least privileged) |
| Read back | `GET /me/events/{id}?$select=id,isCancelled,attendees` | attendee `status.response` per attendee |
| Cancel | `POST /me/events/{id}/cancel` by the organizer | an attendee calling it gets HTTP 400 |
| Delete / update | not used | `DELETE`, `PATCH` exist |

- A created event is **Pending**. **Accepted** or **Declined** only after the resource attendee's own response is read back; `none`, `notResponded` and `tentativelyAccepted` stay Pending; unknown values become Unknown.
- Conflicts: a free resource with `AutomateProcessing AutoAccept` accepts, a conflicting request is declined by Exchange (default `AllowConflicts` false). The `getSchedule` pre-check is advisory; a local overlap guard prevents double requests from PlaceHub. Competing requests are decided by Exchange; a decline frees the slot in PlaceHub.
- Outlook changes: refresh reconciles externally cancelled or removed events (state Cancelled); a read failure never downgrades an Accepted reservation.
- Ambiguous create or cancel (timeout, 5xx) becomes `RequiresReconciliation` and is never retried blindly; only HTTP 429 is retried (rejected before processing; `transactionId` is also sent).
- Open item: the exact response timing of a real equipment mailbox and the resulting UX are unverified.

### Exact consent request (prepared, NOT executed, NOT authorized)

`scripts/Invoke-PlaceHub-Requirements.ps1 PrepareConsent` writes `artifacts/consent-request-booking.md`:

- Application `placehub-frontend-development` only; Microsoft Graph **delegated** `Calendars.ReadWrite` (`1ec239c2-d7c9-4623-a91a-a9775856bb36`, tenant type User). Microsoft documents `AdminConsentRequired = No`; the tenant consent policy decides, and a tenant-wide administrator consent is requested for consistency with the read scopes.
- Not requested: any application permission (`ef54d2bf-783f-4e0f-bca1-3210c0444d99`), `Calendars.ReadWrite.Shared`, anything on the provisioning application.
- **Residual risk:** `Calendars.ReadWrite` is write access to all of the signed-in user's calendar events; no narrower delegated permission exists for creating events. Controls: fixed typed bodies, organizer-only cancel, no arbitrary Graph URLs, boundary tests, closed gates.
- Required before any grant: ADR-007 and ADR-006 acceptance; declaration through the ADR-016 workflow (policy amendment, exact plan, apply); change of the web token provider allowlist (currently refuses the scope, tested); Project Owner and security acceptance of the residual risk.

**Decision requested:** accept booking writes for development with the residual risk; accept the Pending/Accepted state model; approve the consent request and the Terraform declaration as separate steps.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).
- Microsoft Learn: https://learn.microsoft.com/en-us/graph/api/calendar-getschedule?view=graph-rest-1.0
- Microsoft Learn: https://learn.microsoft.com/en-us/exchange/recipients/equipment-mailboxes

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
