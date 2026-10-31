# ADR-010: Database and Persistence Strategy

- **Status:** Proposed (nicht genehmigt)
- **Priority:** P1
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Decision owner:** Noch festzulegen
- **Governance:** New ADR Required; vor Annahme bestehende Repository-ADRs prüfen

## Context
Parking-Metadaten, Besuche, Rollenbindungen und Audits benötigen möglicherweise lokale Persistenz; Microsoft-Daten sollen nicht dupliziert werden.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Database and Persistence Strategy** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Proposed Decision
Relationale Datenbank für ergänzende Metadaten, Besucher, Einstellungen, Audit-/Korrelationseinträge; SQL Server vs PostgreSQL offen; keine autoritative Buchungskopie.

## Alternatives Considered
Ohne DB (zu begrenzt für Besucher/Metadaten); Document Store (nicht nötig); relationale DB (vorgeschlagen).

## Rationale
Transaktionale Verwaltung lokaler Daten bei einfacher Betriebsführung.

## Consequences and Trade-offs
Migrationen, Backups, GDPR-Löschung und Schemaänderungen erforderlich.

## Security and Privacy Implications
Verschlüsselung, Zugriffsbeschränkung, PII-Retention und Audit-Zugriffskontrolle.

## Dependencies
ADR-005, ADR-006, ADR-008, ADR-011.

## Validation / Proof of Concept
Hosting, Mandantenmodell, Datenmengen und SQL-Server/PostgreSQL-Betriebsrestriktionen klären.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- **Approval gate:** Entscheidung bleibt bis zur expliziten Architekturfreigabe `Proposed`.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
