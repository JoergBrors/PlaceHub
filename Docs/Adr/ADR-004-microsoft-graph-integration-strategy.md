# ADR-004: Microsoft Graph Integration Strategy

- **Status:** Proposed (nicht genehmigt)
- **Priority:** P0
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Decision owner:** Noch festzulegen
- **Governance:** New ADR Required; vor Annahme bestehende Repository-ADRs prüfen

## Context
Places- und Exchange-Funktionen sind nicht notwendigerweise durch dieselbe API und denselben Berechtigungskontext zugänglich.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Microsoft Graph Integration Strategy** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Proposed Decision
Unterstützte Microsoft Graph v1.0-Endpunkte bevorzugen; erforderliche Verwaltungsoperationen über dokumentierte Microsoft-365-Verwaltungsschnittstellen in getrenntem privilegiertem Kontext. Beta nicht standardmäßig für Produktion.

## Alternatives Considered
Direkter SDK-Zugriff aus der UI (starke Kopplung); PowerShell für alles (ungeeignet für interaktive Abläufe); API-Adapter mit differenziertem Zugriff (bevorzugt).

## Rationale
Austauschbare Integration und getrennte Berechtigungsgrenzen.

## Consequences and Trade-offs
Versions-, Paging-, Throttling-, Retry- und API-Änderungsmanagement erforderlich.

## Security and Privacy Implications
Explizite delegated/application permissions pro Use Case; eingeschränkter Mailbox-Scope; keine pauschalen tenantweiten Schreibrechte.

## Dependencies
ADR-005, ADR-009, ADR-015.

## Validation / Proof of Concept
Capability Matrix mit v1.0/Beta, Berechtigungen, Lizenz, Consent und Testtenant-Ergebnissen vervollständigen.

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
