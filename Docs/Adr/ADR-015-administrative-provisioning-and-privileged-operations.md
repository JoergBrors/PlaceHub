# ADR-015: Administrative Provisioning and Privileged Operations

- **Status:** Accepted for development isolated-worker architecture
- **Priority:** P0
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Approval date:** 2026-11-01
- **Decision authority:** Project Owner approval
- **Governance:** Isolated worker, Exchange Online PowerShell and worker-only Key Vault accepted; effective privilege remains gated

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

## Accepted identity refinement
`placehub-m365-provisioning-development` ist eine isolierte app-only Identität. `Exchange.ManageAsApp` kommt nur für den nachgewiesenen PowerShell-Verwaltungsweg zusammen mit minimaler Exchange Custom RBAC Role und Resource Scope infrage; Exchange Administrator und eine Wiederverwendung durch Web- oder Terraform-Workflows sind ausgeschlossen.

Die vorgeschlagene Authentifizierung verwendet ein CSP-basiertes exportierbares RSA-Zertifikat und niemals einen Client Secret; CNG ist für diesen Exchange-CBA-Pfad ausgeschlossen. Ein typisierter Adapter ruft ausschließlich `Connect-ExchangeOnline`, die freigegebenen Mailbox-/CalendarProcessing-Cmdlets und `Disconnect-ExchangeOnline` in einem separaten Worker auf. Key Vault ist optional und kostenpflichtig; der private Schlüssel darf nur für die notwendige `X509Certificate2`-Nutzung kurzzeitig im Worker-Speicher vorliegen. Details und Restprivilegien stehen in `../exchange-provisioning-architecture.md`.

Im initialen PoC ist der Adapter standardmäßig ein nicht privilegierter Mock. Für einen später separat genehmigten Testtenant-Nachweis wird zuerst ein gehärteter lokaler Windows-Worker mit OS-geschütztem Zertifikatsspeicher verwendet. Der Docker Socket und Host-Zertifikatsspeicher dürfen nie in den Webcontainer gemountet werden; ein Linux-Worker-Container benötigt einen eigenen Kompatibilitäts- und Isolationsnachweis.

Im Windows-Zertifikatsspeicher darf der CSP-basierte private Schlüssel zur Laufzeit nicht exportierbar sein, sofern Enrollment/Rotation ohne PFX-Transfer auskommen; der Worker greift per Thumbprint unter dem dedizierten Servicekonto zu. Exportierbarkeit ist nur für einen ausdrücklich genehmigten Enrollment-/Transferpfad oder eine zukünftige Key-Vault-zu-`X509Certificate2`-Lösung erforderlich, nicht generell für Exchange-CBA aus dem lokalen Store.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Accepted UI-driven workflow amendment

Office/Location Managers submit location-bound typed requests; a PlaceHub System Administrator may approve and trigger eligible operations without holding an Exchange administrator role. Approval does not grant Microsoft 365 access. A separately authenticated worker revalidates request version, approval, location, idempotency and fixed operation/parameter policy before execution. The state model is Draft, Submitted, AwaitingApproval, Approved, Rejected, Running, PendingPropagation, Succeeded, Failed, PartiallyConfigured and RequiresReconciliation. Approved payloads are immutable, approval replay is rejected and arbitrary PowerShell input is impossible. Narrow automatic approval remains disabled until a separate operation policy is accepted.

The offline POC implements this shape with an in-process mock adapter only; it has no certificate, token, Graph/Exchange client or tenant access. A live worker, effective permissions, consent, Exchange custom RBAC, mailbox-creation residual scope, certificate lifecycle and durable execution store remain explicit approval gates.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- Effective Graph/Exchange permission, consent, custom RBAC, certificate enrollment, exact operation allowlists and mailbox-create residual risk remain separate security gates.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).
- Microsoft Learn: https://learn.microsoft.com/en-us/graph/api/place-post?view=graph-rest-1.0
- Microsoft Learn: https://learn.microsoft.com/en-us/microsoft-365/places/powershell/new-place
- Microsoft Learn: https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.

## Proposed amendment: Microsoft Places write path (2026-11-01)

**Status: PROPOSED.** The Project Owner asked in chat on 2026-11-01 to approve the ADR changes for this write path; the exact text below awaits confirmation before it is marked Accepted. Until then the existing accepted decisions above remain in force and no tenant write is authorized.

**Decision proposed.** The worker's Places writes use Graph v1.0 (ADR-004 amendment) with app-only authentication through the existing isolated workload identity `placehub-m365-provisioning-development` (certificate, worker-only Key Vault access per the accepted Key Vault amendment). Exchange RBAC for Applications is created for that service principal only, with the smallest roles: `TenantPlacesManagement` for hierarchy operations and, only if mailbox creation is separately approved, `MailRecipient` with a management scope limiting it to PlaceHub-marked recipients where the scope mechanism supports it.

**Residual risk to approve explicitly.** `MailRecipient` can manage users and mailboxes. Creating workspaces (and reservable desks) creates mailboxes implicitly, so hierarchy-only creation (building, floor, section) is the first stage and needs no mailbox privilege as far as documented; this is to be verified empirically in the development tenant before any `MailRecipient` assignment.

**Typed request contract (extends ADR-017).** Allowlisted resource types and parameters (`displayName`, `parentId`, documented tags and mode only), immutable approved payload, idempotency key, transactional claim, lease and heartbeat, bounded retries, external read-after-write verification, states `PendingPropagation` and `RequiresReconciliation` for ambiguous outcomes, and no automatic duplicate creation (search by name and parent before retrying a timed-out create). The web process never receives the worker credential, a Key Vault grant or an app-only token.

**Gates (all still open).** Accepting this amendment; exact development resource names; effective `Place.ReadWrite.All` application permission and consent; Exchange RBAC assignment; certificate enrollment and Key Vault access; first-building bootstrap policy; mailbox-create residual scope; an ADR-016-conformant Terraform plan and apply.
