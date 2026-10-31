# ADR-014: Testing Strategy

- **Status:** Accepted
- **Priority:** P1
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Approval date:** 2026-10-31
- **Decision authority:** Project Owner approval
- **Governance:** Accepted for the initial local PoC test strategy

## Context
Die Architektur enthält externe abhängige Cloud-Dienste mit Berechtigungs- und Lizenzgrenzen.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Testing Strategy** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Decision
Unit- und Architekturtests ohne Cloud, Contract-/Integrationsprüfungen mit Testtenant, gezielte End-to-End-Flows für Places, Visitor und Parking.

## Alternatives Considered
Nur E2E (langsam und fragil); ausschließlich Mocking (unzureichend für Graph/Exchange); abgestufte Strategie (vorgeschlagen).

## Rationale
Schnelles Feedback und verifizierte Schnittstellen.

## Consequences and Trade-offs
Testtenant, stabile Fixtures, sichere Testdaten und Berechtigungswartung notwendig.

## Security and Privacy Implications
Keine Produktions-Tenant-Tests; synthetische Besucher; dedizierte Testidentitäten mit Least Privilege.

## Dependencies
ADR-003, ADR-004, ADR-007, ADR-009.

## Validation / Proof of Concept
Abnahmekriterien und kritische PoC-Szenarien in automatisierbare Testfälle überführen.

## Accepted local container scope
Zusätzlich werden deterministischer Image-Build, SBOM/Vulnerability Policy, Non-root/Read-only-Compose-Regeln, Health/Readiness, SQLite-Migration/Lock/Reset, exakte Localhost-OIDC-Callbacks, Secret-/Log-Canaries und Offline-Mocks geprüft. Live-Microsoft-365-Tests bleiben separat genehmigte Testtenant-Vorgänge.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- Live test-tenant operations and future cloud/production test environments require separate authorization.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).
- Microsoft Learn: https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-10/overview

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
