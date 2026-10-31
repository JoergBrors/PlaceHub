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
Negativtests müssen insbesondere Web-zu-Provisioning-Eskalation, nicht freigegebene Cmdlets/Parameter und Zugriffe auf nicht markierte Mailboxen abweisen.
Konkrete Create-/Update-Operationen, Role Assignments, Scopes und Rückabwicklung verifizieren.

## Proposed identity refinement (not approved)
`placehub-m365-provisioning-development` ist eine isolierte app-only Identität. `Exchange.ManageAsApp` kommt nur für den nachgewiesenen PowerShell-Verwaltungsweg zusammen mit minimaler Exchange Custom RBAC Role und Resource Scope infrage; Exchange Administrator und eine Wiederverwendung durch Web- oder Terraform-Workflows sind ausgeschlossen.

Die vorgeschlagene Authentifizierung verwendet ein CSP-basiertes exportierbares RSA-Zertifikat und niemals einen Client Secret; CNG ist für diesen Exchange-CBA-Pfad ausgeschlossen. Ein typisierter Adapter ruft ausschließlich `Connect-ExchangeOnline`, die freigegebenen Mailbox-/CalendarProcessing-Cmdlets und `Disconnect-ExchangeOnline` in einem separaten Worker auf. Key Vault ist optional und kostenpflichtig; der private Schlüssel darf nur für die notwendige `X509Certificate2`-Nutzung kurzzeitig im Worker-Speicher vorliegen. Details und Restprivilegien stehen in `../exchange-provisioning-architecture.md`.

Im initialen PoC ist der Adapter standardmäßig ein nicht privilegierter Mock. Für einen später separat genehmigten Testtenant-Nachweis wird zuerst ein gehärteter lokaler Windows-Worker mit OS-geschütztem Zertifikatsspeicher verwendet. Der Docker Socket und Host-Zertifikatsspeicher dürfen nie in den Webcontainer gemountet werden; ein Linux-Worker-Container benötigt einen eigenen Kompatibilitäts- und Isolationsnachweis.

Im Windows-Zertifikatsspeicher darf der CSP-basierte private Schlüssel zur Laufzeit nicht exportierbar sein, sofern Enrollment/Rotation ohne PFX-Transfer auskommen; der Worker greift per Thumbprint unter dem dedizierten Servicekonto zu. Exportierbarkeit ist nur für einen ausdrücklich genehmigten Enrollment-/Transferpfad oder eine zukünftige Key-Vault-zu-`X509Certificate2`-Lösung erforderlich, nicht generell für Exchange-CBA aus dem lokalen Store.

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
