# ADR-007: Parking Reservations and Consistency

- **Status:** Proposed (nicht genehmigt)
- **Priority:** P0
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Decision owner:** Noch festzulegen
- **Governance:** New ADR Required; vor Annahme bestehende Repository-ADRs prüfen

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
