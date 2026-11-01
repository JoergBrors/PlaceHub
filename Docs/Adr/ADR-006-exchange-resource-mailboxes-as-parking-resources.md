# ADR-006: Exchange Resource Mailboxes as Parking Resources

- **Status:** Proposed; Exchange Online PowerShell worker interface accepted
- **Priority:** P0
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Decision owner:** Noch festzulegen
- **Governance:** New ADR Required; vor Annahme bestehende Repository-ADRs prüfen

## Context
Parkplätze sollen als Geschäftsfunktion sichtbar sein, obwohl Exchange Kalender und Buchungslogik hält.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Exchange Resource Mailboxes as Parking Resources** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Proposed Decision
Ein einzelnes Exchange-Resource-Mailbox-Objekt je Parkplatz; Equipment Mailbox bevorzugter Kandidat, Room Mailbox ausdrücklich als Alternative zu testen; lokale Ergänzungsmetadaten separat.

## Alternatives Considered
Equipment Mailbox (Kandidat); Room Mailbox (Alternative); lokale Booking-Engine (nicht bevorzugt).

## Rationale
Nutzt bestehende Kalender- und Resource-Booking-Funktionen.

## Consequences and Trade-offs
Bereitstellung, Umbenennung, Deaktivierung und Postfachzuordnung werden eigene Workflows.

## Security and Privacy Implications
Mailbox-Scopes, minimal erforderliche Kalenderrechte, separate Provisionierungsidentität.

## Dependencies
ADR-004, ADR-007, ADR-010, ADR-015.

## Validation / Proof of Concept
AutoAccept, Kalenderdetails, Graph-Zugriff, Booking-Policy und Mailbox-Typ im Testtenant vergleichen.

## Proposed authorization refinement (not approved)
App-only Kalenderzugriff muss durch Exchange Application RBAC auf ausdrücklich markierte Entwicklungs-Parkplatzpostfächer begrenzt und mit erlaubten wie abgelehnten Postfächern getestet werden. Die Bereitstellung verwendet eine getrennte Identität und eine minimale Custom Role; das Scope-Problem bei neu anzulegenden Postfächern bleibt ein Approval Gate.

Für die Verwaltung ist zertifikatsbasierte App-only-Authentifizierung mit `placehub-m365-provisioning-development` vorgeschlagen. Da ein Resource Scope ein noch nicht existierendes Postfach nicht zuverlässig begrenzen kann, bleibt entweder die menschliche Erstellung mit anschließender Markierung oder die explizite Akzeptanz einer verbleibenden organisationsweiten Create-Berechtigung erforderlich. Löschung ist nicht Teil des vorgeschlagenen Adapters.

Der lokale PoC verwendet ausschließlich Mocks. Equipment Mailbox bleibt der bevorzugte Kandidat, Room Mailbox bleibt Bestandteil des Testtenant-Vergleichs. Eine organisationsweite automatische `New-Mailbox`-Berechtigung ist nicht genehmigt.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Proposed UI-lifecycle amendment (not approved)

Parking and desk-pool provisioning are distinct typed workflows. Parking retains Equipment Mailbox as candidate and Room Mailbox as a test alternative; desk pools use the separately proposed Room-to-Workspace process. UI actions create approved requests only. Disable is reversible, deletion is excluded, and Exchange calendar state remains authoritative. Automatic mailbox creation stays blocked until security explicitly accepts the residual organization-wide create capability, approved SMTP/naming/type templates, immediate scope marking, quarantine on partial failure and reconciliation.

## Accepted interface boundary (2026-11-01)

Project Owner approval selects Exchange Online PowerShell in the isolated worker as the development provisioning interface. This does not select Equipment versus Room Mailbox, authorize `New-Mailbox`, accept organization-wide residual create privilege, grant `Exchange.ManageAsApp`, approve consent or permit a tenant mutation.

## Recommendation for the Project Owner (PROPOSED, 2026-11-01 – not a decision)

**Status: PROPOSED – not Accepted.** Evidence: Microsoft Learn (manage resource mailboxes, equipment mailboxes, Set-CalendarProcessing, app-only authentication, `POST /places`), checked 2026-11-01. Nothing here authorizes creation, permissions or a live runner.

### Recommended model: Equipment mailbox (`RecipientTypeDetails = EquipmentMailbox`)

- Microsoft defines an equipment mailbox as a resource that is **not location specific** (portable computer, projector, company car); a room mailbox is a resource assigned to a physical location and is organized in room lists and in Microsoft Places as a `room`. A parking space is a resource to reserve, not a meeting room.
- Equipment is booked as an **attendee or location** of the organizer's event; Microsoft advises never to make an equipment mailbox the organizer. This is exactly the delegated organizer-based booking model of ADR-007.
- Using rooms would place parking spaces into Room Finder and the Places room directory, mixing them with meeting rooms. ADR-006 already requires that a parking space must not be inferred to belong to the Places desk or workspace hierarchy; the building association therefore lives in PlaceHub-owned metadata.
- The choice is **reversible**: Microsoft documents converting between resource mailbox types (`Set-Mailbox -Type`), and both types support the same `Set-CalendarProcessing` options. Resource mailboxes need no license.
- Trade-offs accepted: no native Places parent (location is PlaceHub metadata), no capacity or room-list features. If native Places parentage for parking is required later, the type can be changed with a read-back-verified request.

### Naming (already enforced by the typed contract)

Name prefix `PH-PARK-` (pattern `^[A-Za-z0-9][A-Za-z0-9 _-]{1,63}$`), lowercase alias `ph-park-<site>-<nn>` (`^[a-z0-9][a-z0-9-]{1,63}$`), SMTP address on an approved verified domain only, display name `Parkplatz <Standort> <Nr>`. No free-form names, no shell metacharacters; the domain list and prefix are worker options and refuse creation while empty.

### Booking policy templates (proposed values, documented parameters only)

| Template | AutomateProcessing | AllowConflicts | BookingWindowInDays | MaximumDurationInMinutes | AllowRecurringMeetings |
|---|---|---|---|---|---|
| `standard` | AutoAccept | False | 14 | 1440 | False |
| `restricted` | AutoAccept | False | 7 | 600 | False |

Microsoft documents `BookingWindowInDays` 0–1080 (default 180; 0 means today) and `MaximumDurationInMinutes` default 1440. Exchange's default is that anyone can book and bookings are accepted automatically when the resource is free; conflicts are declined by the Resource Booking Assistant. Recommended addition before live use: make the "who may book" intent explicit with `AllBookInPolicy` (and `BookInPolicy`), which needs a separate parameter-allowlist entry and a decision on group-based scoping (only non-nested groups work).

### Disable semantics (recommended, staged)

1. **Stage 1 – PlaceHub-level disable:** metadata status and booking gate only. No Exchange right, fully reversible, immediately effective inside PlaceHub. Recommended as the only disable in the first release.
2. **Stage 2 – Exchange-level block (needs a development proof first):** Microsoft's documented scoped-approval pattern (`AutomateProcessing AutoAccept`, `AllBookInPolicy $false`, `AllRequestInPolicy $false`, `BookInPolicy` limited) auto-declines everyone else. The behavior with an empty `BookInPolicy` list is **not documented** and must be verified on a development resource before it is adopted.
3. Never `Remove-Mailbox`; deletion stays outside PlaceHub.

### Recovery and reconciliation

Every state is derived from read-back (`Get-EXOMailbox`, `Get-CalendarProcessing`): `MAILBOX_ALREADY_EXISTS`, `READ_AFTER_WRITE_MISMATCH` and ambiguous creates end in `RequiresReconciliation`, never in a second create. Type conversion and template re-application are the reversal paths. PlaceHub metadata is non-authoritative and can be rebuilt by importing mailboxes.

### Security implications (to be accepted or rejected explicitly)

- `New-Mailbox` cannot be scoped to a not-yet-existing object, so automatic creation implies organization-wide creation capability for the worker. Alternatives: (a) administrators create the mailbox by their own process and PlaceHub only imports and configures it (recommended for the first release, no creation right); (b) automatic creation with the compensating controls below.
- Compensating controls if (b): custom Exchange role group for the worker's service principal containing only `Get-EXOMailbox`, `Get-CalendarProcessing`, `New-Mailbox`, `Set-Mailbox` (DisplayName) and `Set-CalendarProcessing`; fixed parameter allowlist and value patterns; approved domain and prefix; four-eyes approval; audit; no Entra directory role.
- App-only Exchange PowerShell needs `Exchange.ManageAsApp`, a **CSP-based** certificate (CNG is unsupported) and role assignment; Entra roles such as Exchange Administrator cannot be customized or scoped and are not proposed.

**Decision requested:** equipment versus room; creation model (a) or (b); disable semantics Stage 1 only or Stage 1 plus a verified Stage 2; booking template values; approved SMTP domain and name prefix.

## Open Questions / Approval Gates

- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- **Approval gate:** Entscheidung bleibt bis zur expliziten Architekturfreigabe `Proposed`.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).
- Microsoft Learn: https://learn.microsoft.com/en-us/graph/api/calendar-getschedule?view=graph-rest-1.0
- Microsoft Learn: https://learn.microsoft.com/en-us/exchange/recipients/equipment-mailboxes

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
