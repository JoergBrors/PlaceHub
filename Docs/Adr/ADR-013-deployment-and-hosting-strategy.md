# ADR-013: Deployment and Hosting Strategy

- **Status:** Accepted
- **Priority:** P1
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Approval date:** 2026-10-31
- **Decision authority:** Project Owner approval
- **Governance:** Accepted for the local-first initial PoC; cloud hosting requires an amendment

## Context
Das Projekt nennt Azure und On-Premises als denkbare Hostingziele, ohne Entscheidung.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Deployment and Hosting Strategy** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Decision
Run the initial modular-monolith PoC locally as one Linux-compatible web image under Docker Compose with zero incremental Azure cost. Azure App Service custom containers or another host are future, separately funded amendment candidates.

## Alternatives Considered
Azure App Service (Kandidat); On-Premises IIS/Container (Kandidat); Kubernetes (ohne Anforderung nicht empfohlen).

## Rationale
Minimale Betriebsbausteine und klare Verantwortlichkeit.

## Consequences and Trade-offs
Hostingentscheid beeinflusst Secret-Verwaltung, Skalierung und Datenbankwahl.

## Security and Privacy Implications
TLS, Managed Identity soweit verfügbar, Secret Store, Netzwerk- und Deployment-Rollen, Backups.

## Dependencies
ADR-001, ADR-009, ADR-010, ADR-012.

## Validation / Proof of Concept
Betriebsanforderungen, Netzwerk, Compliance, Konnektivität und Kosten klären.

## Accepted local-first scope
Der initiale PoC läuft mit Docker Compose auf einem lokalen Entwicklerhost und erzeugt keine neuen Azure-Kosten oder Azure-Ressourcen. Ein Linux-kompatibles, nicht als root laufendes Web-Image, ein benanntes SQLite-Volume und lokale Mocks bilden die Ausgangstopologie. Azure Free Tiers sind kein Ersatz für lokales Hosting. App Service Custom Container oder ein anderer Host bleiben eine später finanzierte, separat zu genehmigende Option; Compose, Volume, Identität und lokale Secrets migrieren nicht automatisch.

Der privilegierte Exchange-Worker läuft weder im Webcontainer noch zunächst als Sidecar. Ein gehärteter lokaler Windows-Prozess wird vor einem Linux-Worker-Container geprüft. Key Vault und dedizierter Azure-Worker bleiben kosten- und hostingpflichtige Approval Gates.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- Any Azure hosting, registry, identity, Key Vault, network, monitoring or production deployment requires an amendment and cost approval.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).
- Microsoft Learn: https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-10/overview

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
