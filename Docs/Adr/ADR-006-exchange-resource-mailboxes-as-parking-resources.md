# ADR-006: Exchange Resource Mailboxes as Parking Resources

- **Status:** Proposed (nicht genehmigt)
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
