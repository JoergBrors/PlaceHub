# ADR-005: Microsoft Places Data Model and Hierarchy

- **Status:** Proposed (nicht genehmigt)
- **Priority:** P0
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Decision owner:** Noch festzulegen
- **Governance:** New ADR Required; vor Annahme bestehende Repository-ADRs prüfen

## Context
Geschäftliche Begriffe wie Desk Pool müssen auf das tatsächliche Microsoft-Places-Modell abgebildet werden.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Microsoft Places Data Model and Hierarchy** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Proposed Decision
Building → Floor → Section; Workspace/Desk und Rooms entsprechend dem dokumentierten Places-Modell verknüpfen; Desk Pool als Workspace nur nach konkreter API-/Tenantprüfung. Keine konkurrierende lokale Stammdatenhierarchie.

## Alternatives Considered
Eigene Hierarchie (Datenkonflikte); Komplettspiegelung (hoher Sync-Aufwand); native Places-IDs (bevorzugt).

## Rationale
Respektiert Microsoft 365 als Source of Truth.

## Consequences and Trade-offs
Funktionen und Objektbeziehungen variieren ggf. je API und Lizenz; lokale Metadaten separat halten.

## Security and Privacy Implications
Standortbezogene Zugriffsprüfung unabhängig von eventuell tenantweit wirkenden Graph-Berechtigungen.

## Dependencies
ADR-004, ADR-010, ADR-011.

## Validation / Proof of Concept
CRUD- und Parent/Child-Funktionen in Testtenant prüfen; Desk Pool vs. Workspace und Einzelplatzbuchungen validieren.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- **Approval gate:** Entscheidung bleibt bis zur expliziten Architekturfreigabe `Proposed`.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).
- Microsoft Learn: https://learn.microsoft.com/en-us/graph/api/place-post?view=graph-rest-1.0
- Microsoft Learn: https://learn.microsoft.com/en-us/microsoft-365/places/powershell/new-place

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
