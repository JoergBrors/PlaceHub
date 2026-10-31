# ADR-009: Authentication and Authorization

- **Status:** Proposed (nicht genehmigt)
- **Priority:** P0
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Decision owner:** Noch festzulegen
- **Governance:** New ADR Required; vor Annahme bestehende Repository-ADRs prüfen

## Context
Office Management soll keine Tenant-Administratorrolle für alltägliche Fachaufgaben benötigen.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Authentication and Authorization** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Proposed Decision
OIDC/Entra-Anmeldung; Rollen- und Standortberechtigungen serverseitig; technische Graph-/Exchange-Berechtigungen separat je Workflow mit delegated/application-Modell.

## Alternatives Considered
Tenant-Admin-Rollen als Fachrollen (zu privilegiert); eigene Identität (unnötig); Entra + App-RBAC (bevorzugt).

## Rationale
Least Privilege bei guter Benutzererfahrung.

## Consequences and Trade-offs
Rollen-/Standortmodell und Ressourcenzuordnung müssen gepflegt werden.

## Security and Privacy Implications
Token serverseitig, AuthZ auf jedem Use Case, Audit, scope-beschränkte App-Berechtigungen; Privileged Provisioning getrennt.

## Dependencies
ADR-004, ADR-015.

## Validation / Proof of Concept
Rechte-Matrix, Consent, Site-/Mailbox-Scope und Negativtests im Testtenant prüfen.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- **Approval gate:** Entscheidung bleibt bis zur expliziten Architekturfreigabe `Proposed`.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).
- Microsoft Learn: https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
