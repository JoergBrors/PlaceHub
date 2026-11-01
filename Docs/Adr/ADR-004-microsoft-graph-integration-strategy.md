# ADR-004: Microsoft Graph Integration Strategy

- **Status:** Accepted for development live-read architecture; write permissions remain proposed
- **Priority:** P0
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Approval date:** 2026-11-01
- **Decision authority:** Project Owner approval
- **Governance:** Graph v1.0 reads and Exchange Online PowerShell boundary accepted; effective permissions and writes remain gated

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

## Proposed permission refinement (not approved)
Delegierte Berechtigungen sind für interaktive Lese- und Buchungsvorgänge der Ausgangspunkt; Anwendungsberechtigungen bleiben der isolierten Provisionierungsidentität und separat begründeten unattended Use Cases vorbehalten. Die exakten Kandidaten-IDs, Consent-Anforderungen und Dokumentationsabweichungen stehen in `../entra-application-permission-architecture.md`.

Exchange Equipment Mailbox provisioning and booking-policy configuration use the supported ExchangeOnlineManagement interface in a separate privileged worker, not Graph or EWS. Graph remains responsible for supported scheduling operations. The detailed boundary remains unapproved in `../exchange-provisioning-architecture.md`.

For the local PoC, Graph and Exchange adapters are offline mocks by default. EWS and EWS Managed API are prohibited. Exact operations, permission IDs, tenant capability/licensing and consent remain test-tenant evidence gates.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Accepted Phase-2 read-only amendment

Use Microsoft Graph v1.0 typed Places list/descendant endpoints for Building, Floor, Section, Workspace and Desk reads, and delegated `getSchedule` only for advisory free/busy. Normal runtime is fail-closed Live-First; OfflineMock is limited to an explicit synthetic test profile. Microsoft365ReadOnly requires valid tenant identity, application role, location assignment, delegated scope and target-resource authorization. No write endpoint is approved by this read-only decision.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- Graph/Exchange permission declarations, effective consent, calendar writes and tenant tests require separate authorization.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).
- Microsoft Learn: https://learn.microsoft.com/en-us/graph/api/place-post?view=graph-rest-1.0
- Microsoft Learn: https://learn.microsoft.com/en-us/microsoft-365/places/powershell/new-place

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.

## Accepted amendment (target architecture): Microsoft Places write path (2026-11-01)

**Status: ACCEPTED as target architecture (Project Owner, 2026-11-01).** Approval wording: "ADR-004, ADR-005, ADR-015 und ADR-017 als Zielarchitektur freigeben, ohne operative Rechtefreigabe". This accepts the design only. NOT approved and still gated separately: effective Graph or Exchange permissions and consent, Exchange RBAC assignment, Terraform declarations and apply, worker identity, certificate and Key Vault access, worker activation, automatic mailbox creation, the bootstrap manifest content and any tenant write.

**Decision.** Microsoft Graph v1.0 `POST /places` (and update operations on the same resource) is the preferred interface for creating and updating the Places hierarchy (building, floor, section, room, workspace, desk), executed only by the isolated provisioning worker with app-only authentication. Office Management never holds or uses a delegated Places write permission; the web application keeps only delegated `Place.Read.All` and `Calendars.ReadBasic`. No beta endpoint is used. Exchange Online PowerShell (ADR-015) is retained, unchanged, for Exchange resource-mailbox administration (mailbox, `Set-CalendarProcessing`); the two interfaces are not interchangeable and a Places hierarchy operation is not routed to PowerShell without a separate decision.

**Documented prerequisites (Microsoft Learn, checked 2026-11-01).**
- Application `POST /places` requires `Place.ReadWrite.All` **and** both Exchange roles `TenantPlacesManagement` (manage Places) and `MailRecipient` (manage users and mailboxes). Hierarchy-only creation (building, floor, section) is **not** documented as exempt from `MailRecipient`; no exemption is assumed until a supported technical proof exists in the development tenant.
- Delegated use requires an Entra role (least privileged: Exchange Administrator), which Office Managers must not hold.
- Graph creates workspaces with a generated `emailAddress`, i.e. a mailbox is created as a side effect.

**Unresolved capability assumptions (must be proven, not assumed).**
1. Whether `TenantPlacesManagement` and `MailRecipient` can be assigned to a service principal through Exchange RBAC for Applications. That article lists its supported application roles and names neither, while the Graph article points to it for exactly these roles.
2. Whether a recipient scope (management scope or administrative unit) takes effect for these roles and limits `MailRecipient` to PlaceHub-marked recipients. RBAC scopes apply to recipients, not to Places directory objects.
3. The Places documentation is inconsistent on whether one or both roles are required for `Set-PlaceV3`; the stricter reading (both) is applied.

**Narrowing is limited by documented platform behavior.** Application roles cannot be copied or derived, so no custom narrower role can be built. Exchange RBAC grants are additive to Entra grants, so a tenant-consented `Place.ReadWrite.All` is not narrowed by any Exchange scope.

**Mailbox side effects are not authorized here.** This decision authorizes no automatic creation of workspace or desk mailboxes. Creating a workspace or a Reservable/DropIn desk requires its own approval of the mailbox-create residual privilege (ADR-015 amendment).
