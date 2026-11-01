# ADR-009: Authentication and Authorization

- **Status:** Accepted, amended for Live-First development
- **Priority:** P0
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Approval date:** 2026-10-31
- **Decision authority:** Project Owner approval
- **Amendment date:** 2026-11-01
- **Amendment authority:** Project Owner approval
- **Governance:** Accepted identity boundaries; permissions and consent remain separate gates

## Context
Office Management soll keine Tenant-Administratorrolle für alltägliche Fachaufgaben benötigen.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Authentication and Authorization** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Decision
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

## Accepted registration boundary
Der serverseitige Monolith verwendet vorgeschlagen eine single-tenant Confidential-Web-Registrierung mit Authorization Code, serverseitigen Tokens und ohne Implicit/Public-Client-Flow. `PlaceHub.OfficeManager`, `PlaceHub.LocationManager` und `PlaceHub.SystemAdministrator` sind User-App-Role-Kandidaten; jede fachliche Aktion benötigt zusätzlich die serverseitige Standortprüfung.

Eine Office-Manager-Anforderung erzeugt nur nach Rollen- und Standortprüfung einen typisierten Provisionierungsauftrag. Weder Benutzeroberfläche noch Webprozess erhalten Exchange-Admin-Token oder Zertifikatsschlüssel; die getrennte Worker-Identität authentifiziert sich ausschließlich per genehmigtem Zertifikat.

Der lokale PoC verwendet ausschließlich exakt registrierte HTTPS-Localhost-Redirect- und Sign-out-URIs mit festem Port. Es gibt keine Managed Identity im lokalen Webcontainer; Runtime-Identity und Secret Provider sind austauschbare Adapter. Mocks sind Standard, Live-Graph-Aufrufe benötigen weiterhin separat genehmigte delegated permissions.

## Documentation Impact

## Live-First amendment

Normal development runtime requires the existing single-tenant confidential web registration, recognized application role, location assignment and live Microsoft 365 adapters. Missing identity, credential, consent or tenant capability fails closed without mock fallback. Synthetic identities and providers are permitted only through an explicitly selected test profile and can never access live adapters. Effective consent, assignments and confidential credential enrollment remain separate administrative gates.

Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- Exact callbacks, role assignments, scopes, consent and Exchange authorization require separate approval.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).
- Microsoft Learn: https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
