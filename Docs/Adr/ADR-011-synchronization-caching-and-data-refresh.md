# ADR-011: Synchronization, Caching and Data Refresh

- **Status:** Proposed (nicht genehmigt)
- **Priority:** P1
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Decision owner:** Noch festzulegen
- **Governance:** New ADR Required; vor Annahme bestehende Repository-ADRs prüfen

## Context
Places- und Exchange-Daten werden außerhalb von PlaceHub geändert. Caching darf keine falsche Verfügbarkeit vortäuschen.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Synchronization, Caching and Data Refresh** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Proposed Decision
Bei administrativen Übersichten on-demand oder kurzlebiger Cache; Buchungsstatus an Exchange prüfen; Hintergrundabgleich nur für konkrete operative Notwendigkeit.

## Alternatives Considered
Vollreplikation (hohe Komplexität); reines Live-Lesen (Latenz); differenzierte Aktualisierung (vorgeschlagen).

## Rationale
Geringere Drift und kontrollierter API-Verbrauch.

## Consequences and Trade-offs
Staleness-Hinweise und Ausfallverhalten nötig.

## Security and Privacy Implications
Keine ungeschützten PII-Caches; Cache-Isolation nach Benutzer-/Standortrechten.

## Dependencies
ADR-004, ADR-007, ADR-010.

## Validation / Proof of Concept
API-Limits, Änderungsfrequenz, notwendige Refresh-Zyklen und Reconciliation-Fehler prüfen.

## Proposed local PoC refinement (not approved)
Offline Graph-/Exchange-Mocks sind Test-Fixtures und müssen in Datenmodell, UI und Telemetrie eindeutig als nicht-live erkennbar sein. Ein lokaler Cache darf weder Microsoft Places noch Exchange-Buchungen autoritativ ersetzen; TTL, Invalidierung, Sync und Reconciliation bleiben offen.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Proposed Phase-2 read strategy (not approved)

Begin with on-demand Places and availability reads that display source and read timestamp. Do not add a live cache until TTL, invalidation, per-user/location isolation and stale-state UX have test evidence. Paging is bounded, cancellation is propagated and transient 429/503 retries honor bounded `Retry-After`. A cached Places record or free/busy result never becomes an authoritative booking or hierarchy copy.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- **Approval gate:** Entscheidung bleibt bis zur expliziten Architekturfreigabe `Proposed`.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
