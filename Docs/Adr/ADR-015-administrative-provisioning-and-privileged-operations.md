# ADR-015: Administrative Provisioning and Privileged Operations

- **Status:** Proposed (nicht genehmigt)
- **Priority:** P0
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Decision owner:** Noch festzulegen
- **Governance:** New ADR Required; vor Annahme bestehende Repository-ADRs prüfen

## Context
Gebäude-, Desk- oder Mailbox-Provisionierung kann erhöhte Rechte erfordern, ohne dass Office Manager diese direkt besitzen sollen.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Administrative Provisioning and Privileged Operations** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Proposed Decision
Privilegierte Abläufe in isoliertem Zugriffskontext oder kontrolliertem administrativem Workflow; explizite Autorisierung, Audit und Statusführung; kein automatischer Microservice.

## Alternatives Considered
Adminrechte direkt für Office Manager (abgelehnt); tenantweite Dauerrechte (nicht bevorzugt); separat abgesicherte Provisionierung (vorgeschlagen).

## Rationale
Least Privilege und klare Verantwortlichkeiten.

## Consequences and Trade-offs
Operationen können asynchron, genehmigungspflichtig oder nur teilweise erfolgreich sein.

## Security and Privacy Implications
Getrennte Identitäten, begrenzte Scopes, Vier-Augen-Freigabe bei Bedarf, revisionsfähige Audits.

## Dependencies
ADR-004, ADR-009, ADR-012.

## Validation / Proof of Concept
Konkrete Create-/Update-Operationen, Role Assignments, Scopes und Rückabwicklung verifizieren.

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
- Microsoft Learn: https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
