# ADR-003: Backend Architecture with .NET 10

- **Status:** Accepted
- **Priority:** P0
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Approval date:** 2026-10-31
- **Decision authority:** Project Owner approval
- **Governance:** Accepted for the initial modular-monolith implementation

## Context
Microsoft-Graph-SDK-Typen und UI-Komponenten sollen nicht die Fachlogik bestimmen.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Backend Architecture with .NET 10** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Decision
Trennung nach Presentation, Application, Domain und Infrastructure; fachliche Use Cases erhalten abstrahierte Integration-Ports. Keine zwingende Assembly pro Schicht.

## Alternatives Considered
N-Tier (geringere fachliche Trennung); umfassendes DDD (unnötig für einfache CRUD-Anteile); pragmatische Clean Architecture (bevorzugt).

## Rationale
Verbessert Testbarkeit und Austauschbarkeit von Microsoft-Integrationen.

## Consequences and Trade-offs
Mögliches Abstraktions-Overhead muss aktiv begrenzt werden.

## Security and Privacy Implications
Policy- und Use-Case-basierte Autorisierung, Eingabevalidierung, Secrets nicht im Domain-Modell.

## Dependencies
ADR-001, ADR-004, ADR-014.

## Validation / Proof of Concept
Struktur erst nach Repositoryinspektion verbindlich festlegen; Architekturtests für Abhängigkeiten.

## Accepted portability scope
Application und Domain verwenden Ports für Datenbank, Graph, Provisionierung, Konfiguration, Secrets und Runtime Identity. Docker-, Azure-, EF-Provider-, Graph-SDK- und PowerShell-Implementierungen bleiben in Infrastructure/Hosting-Adaptern. Das gleiche Web-Image soll später nach expliziter Kompatibilitätsprüfung auf einem genehmigten Containerhost laufen können.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- Concrete project layout is implementation detail; abandoning the modular monolith requires an amendment.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).
- Microsoft Learn: https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-10/overview

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
