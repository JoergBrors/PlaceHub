# ADR-001: Overall System Architecture

- **Status:** Accepted
- **Priority:** P0
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Approval date:** 2026-10-31
- **Decision authority:** Project Owner approval
- **Governance:** Accepted for the initial local PoC; material changes require an amendment

## Context
Die Anwendung vereint Places, Parking, Visitors und Office-Management-Übersichten. Die Projektvorgabe bevorzugt Einfachheit und fachliche Modularisierung.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Overall System Architecture** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Decision
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

## Accepted local-first scope
Der modulare Monolith wird für den initialen PoC als ein Linux-kompatibles .NET-10-Container-Image ausgeführt. Docker Compose ist nur lokale Orchestrierung; fachliche Module bleiben unabhängig von Docker, Azure und konkreten Microsoft-SDK-Typen. Der getrennte privilegierte Exchange-Worker ist kein Teil des Webprozesses.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- Production topology, scale and material module-boundary changes require separate review.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).
- Microsoft Learn: https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-10/overview

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
