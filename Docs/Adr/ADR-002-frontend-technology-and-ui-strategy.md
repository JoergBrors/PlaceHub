# ADR-002: Frontend Technology and UI Strategy

- **Status:** Accepted
- **Priority:** P0
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Approval date:** 2026-10-31
- **Decision authority:** Project Owner approval
- **Governance:** Accepted for server-side Blazor in the initial local PoC

## Context
Office Management benötigt verständliche Verwaltungsformulare, Übersichten und interaktive Buchungsprozesse, nicht zwingend einen separaten Frontend-Stack.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Frontend Technology and UI Strategy** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Decision
Blazor Web App, serverseitige Interaktivität, serverseitige Microsoft-365-Zugriffe; alternative Rendering-Modi nur nach Bedarfsnachweis.

## Alternatives Considered
Blazor (bevorzugt); React + Web API (mehr Technologie- und Betriebsaufwand); Razor Pages (weniger Komfort bei stark interaktiven Vorgängen).

## Rationale
Einheitlicher .NET-Stack und vereinfachte Serverintegration.

## Consequences and Trade-offs
Persistente Verbindungen und Skalierungsverhalten prüfen; UI- und Geschäftslogik dürfen nicht verschmelzen.

## Security and Privacy Implications
Token und Geheimnisse ausschließlich serverseitig; Backend-Autorisierung unabhängig von UI.

## Dependencies
ADR-001, ADR-003, ADR-009.

## Validation / Proof of Concept
PoC für Kalender, große Tabellen, Verbindungsabbrüche, Barrierefreiheit und Lastverhalten.

## Accepted identity and local scope
Für die vorgeschlagene serverseitige Blazor-Web-App genügt eine einzelne vertrauliche Web-Registrierung. Eine separate Backend-Registrierung wird erst bei unabhängig gehosteter UI/API mit eigener Audience vorgeschlagen. Details und Freigabesperren stehen in `../entra-application-permission-architecture.md`.

Der initiale Blazor-PoC läuft im lokalen Linux-Webcontainer und verwendet eine exakt registrierte feste HTTPS-Localhost-Callback-URI. Rendering, serverseitige Tokenhaltung und Autorisierung dürfen keine App-Service-Abhängigkeit erhalten.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- Exact Entra changes, Graph consent and any independent frontend/API split require separate approval.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).
- Microsoft Learn: https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-10/overview

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
