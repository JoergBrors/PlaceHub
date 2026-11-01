# ADR-005: Microsoft Places Data Model and Hierarchy

- **Status:** Accepted for native development read hierarchy; provisioning method unresolved
- **Priority:** P0
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Approval date:** 2026-11-01
- **Decision authority:** Project Owner approval
- **Governance:** Native IDs and hierarchy accepted; mutation interface remains gated

## Context
Geschäftliche Begriffe wie Desk Pool müssen auf das tatsächliche Microsoft-Places-Modell abgebildet werden.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Microsoft Places Data Model and Hierarchy** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Proposed Decision
Building → Floor → Section; Workspace/Desk und Rooms entsprechend dem dokumentierten Places-Modell verknüpfen; Desk Pool als Workspace nur nach konkreter API-/Tenantprüfung. Keine konkurrierende lokale Stammdatenhierarchie.

## Alternatives Considered
Eigene Hierarchie (Datenkonflikte); Komplettspiegelung (hoher Sync-Aufwand); native Places-IDs (bevorzugt).

## Rationale
Respektiert Microsoft 365 als Source of Truth.

## Consequences and Trade-offs
Funktionen und Objektbeziehungen variieren ggf. je API und Lizenz; lokale Metadaten separat halten.

## Security and Privacy Implications
Standortbezogene Zugriffsprüfung unabhängig von eventuell tenantweit wirkenden Graph-Berechtigungen.

## Dependencies
ADR-004, ADR-010, ADR-011.

## Validation / Proof of Concept
CRUD- und Parent/Child-Funktionen in Testtenant prüfen; Desk Pool vs. Workspace und Einzelplatzbuchungen validieren.

## Proposed permission refinement (not approved)
`Place.Read.All` ist der initiale Lesekandidat. `Place.ReadWrite.All` bleibt unabhängig vom delegated/application-Typ bis zur expliziten Genehmigung interaktiver oder unattended Places-Verwaltung zurückgestellt.

Offline-PoC-Daten müssen eindeutig als Mock gekennzeichnet sein und dürfen keine konkurrierende Places-Hierarchie werden. Desk Pool/Workspace-Fähigkeiten, Objektbeziehungen und Tenant-Lizenzierung bleiben unbestätigt, bis sie gegen aktuelle Microsoft-Dokumentation und den Testtenant geprüft sind.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Proposed UI-administration amendment (not approved)

Desk Pool is represented as a Microsoft Places Workspace beneath the resolved Building → Floor → Section parent, never as an unrelated local grouping. Microsoft currently documents both the explicit Room-mailbox-to-Workspace sequence plus calendar/Places configuration and the newer `New-Place -Type Workspace` automatic mailbox provisioning path. Selection between these paths is an unresolved ADR decision, not an implementation detail. Exact module versions, cmdlets, attributes, licensing, RBAC, propagation and tenant behavior remain test-tenant evidence gates. The offline POC may retain only synthetic IDs, workflow/audit metadata and supplementary display metadata; Microsoft 365 remains source of truth.

For Phase 2, native Graph `placeId`/`parentId` values are the proposed read hierarchy. Workspace capacity, mailbox details or operational metadata that are absent in a supported response remain visibly unknown; PlaceHub must not invent them. Tenant-wide `Place.Read.All` results are filtered again by server-side assigned building/location IDs before reaching the UI.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- Workspace creation/conversion, write permission, licensing and test-tenant evidence remain approval gates.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).
- Microsoft Learn: https://learn.microsoft.com/en-us/graph/api/place-post?view=graph-rest-1.0
- Microsoft Learn: https://learn.microsoft.com/en-us/microsoft-365/places/powershell/new-place

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.

## Proposed amendment: Microsoft Places write path (2026-11-01)

**Status: PROPOSED.** The Project Owner asked in chat on 2026-11-01 to approve the ADR changes for this write path; the exact text below awaits confirmation before it is marked Accepted. Until then the existing accepted decisions above remain in force and no tenant write is authorized.

**Decision proposed.** Hierarchy rules follow the documented model: floor → building, section → floor, room → floor or section, workspace and desk → section. The worker validates the parent type and parent existence before every create and verifies the parent relationship after it.

**Identifiers.** `id` is not immutable; `placeId` is the stable identifier. PlaceHub stores and authorizes by `placeId` and re-reads `id` per operation. Location assignments accept either form but are recorded as `placeId`.

**First-building bootstrap (proposed, development only).** A building cannot require an existing building assignment. A dedicated request kind `BootstrapBuilding` is allowed only when: the environment is `development`; a read-after-check shows zero buildings at approval and again at execution; the payload equals an approved manifest entry (exact display name, no free text); requester and approver are different principals and the approver is a `PlaceHub.SystemAdministrator`; and the request is single-use. Creating the building grants nobody access: the location assignment is a separate, owner-controlled configuration step. SystemAdministrator never becomes tenant-wide.

**Existing resources.** Discovery runs before any create; an empty `200` for buildings does not prove that rooms, room lists or workspaces are absent. No duplicate hierarchy is created; existing resources are imported by `placeId`.
