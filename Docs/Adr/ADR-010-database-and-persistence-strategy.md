# ADR-010: Database and Persistence Strategy

- **Status:** Accepted, amended for durable development queue
- **Priority:** P1
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Approval date:** 2026-10-31
- **Decision authority:** Project Owner approval
- **Amendment date:** 2026-11-01
- **Amendment authority:** Project Owner approval
- **Governance:** Accepted for disposable local-PoC SQLite only; production provider requires an amendment

## Context
Parking-Metadaten, Besuche, Rollenbindungen und Audits benötigen möglicherweise lokale Persistenz; Microsoft-Daten sollen nicht dupliziert werden.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Database and Persistence Strategy** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Decision
SQLite in a named local Docker volume is the relational provider for synthetic, disposable initial-PoC data. It stores only PlaceHub-owned supplementary metadata, settings and audit/correlation test records; it is never an authoritative booking copy. SQL Server versus PostgreSQL remains an explicit later production amendment.

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

## Accepted local PoC scope
Der initiale PoC verwendet SQLite ausschließlich für synthetische, wegwerfbare Daten eines einzelnen Web-Containers. Die Datei liegt in einem benannten Docker Volume; EF-Core-Migrationen werden durch einen kontrollierten einmaligen Schritt ausgeführt, nicht unkontrolliert bei jedem App-Start. Production-PII, Scale-out und Network Filesystems sind ausgeschlossen. SQL Server versus PostgreSQL sowie eine explizite Schema-/Datenmigration bleiben die Produktionsentscheidung; Volume oder SQLite-Datei migrieren nicht automatisch in Azure.

## Documentation Impact

## Durable development queue amendment

SQLite is accepted for the single-instance development request and execution queue defined by ADR-017, including immutable approved payload versions, leases, attempts, heartbeats, notifications and sanitized audit records. This does not approve production data, distributed workers, scale-out, production backup/RTO/RPO or a production persistence provider.

Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- Production provider, real-data classification, retention, backup/RTO/RPO and migration require an amendment.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
