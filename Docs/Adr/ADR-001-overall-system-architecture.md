# ADR-001: Overall System Architecture

- **Status:** Proposed (nicht genehmigt)
- **Priority:** P0
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Decision owner:** Noch festzulegen
- **Governance:** New ADR Required; vor Annahme bestehende Repository-ADRs prüfen

## Context
Die Anwendung vereint Places, Parking, Visitors und Office-Management-Übersichten. Die Projektvorgabe bevorzugt Einfachheit und fachliche Modularisierung.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Overall System Architecture** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Proposed Decision
Eine ASP.NET-Core-Anwendung auf .NET 10 LTS als modularer Monolith; fachliche Grenzen und definierte Schnittstellen für Places, Parking, Visitors, Dashboard, Identity und Administration.

## Alternatives Considered
Microservices (zu hoher operativer Aufwand); unstrukturierter Monolith (schwache Grenzen); modularer Monolith (bevorzugt).

## Rationale
Weniger Deployment- und Integrationskomplexität; fachliche Abgrenzung bleibt testbar.

## Consequences and Trade-offs
Gemeinsame Skalierung und Deployment; modulare Verträge und Abhängigkeitsregeln müssen gepflegt werden.

## Security and Privacy Implications
Autorisierung je Use Case, keine implizite Vertrauensstellung zwischen Modulen.

## Dependencies
ADR-003, ADR-009, ADR-010.

## Validation / Proof of Concept
Modulzuschnitt sowie potenzielle Betriebs- und Performanceanforderungen validieren.

## Proposed local-first refinement (not approved)
Der modulare Monolith wird für den initialen PoC als ein Linux-kompatibles .NET-10-Container-Image ausgeführt. Docker Compose ist nur lokale Orchestrierung; fachliche Module bleiben unabhängig von Docker, Azure und konkreten Microsoft-SDK-Typen. Der getrennte privilegierte Exchange-Worker ist kein Teil des Webprozesses.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- **Approval gate:** Entscheidung bleibt bis zur expliziten Architekturfreigabe `Proposed`.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).
- Microsoft Learn: https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-10/overview

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
