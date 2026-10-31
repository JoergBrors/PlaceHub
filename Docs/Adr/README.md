# PlaceHub – Architecture Decision Record Index

ADR status is recorded individually. ADR-016 is accepted by Project Owner approval dated 2026-10-31. ADR-001 through ADR-015 remain proposed and are not implementation mandates.

| ADR | Title | Priority | Status |
|---|---|---|---|
| [001](ADR-001-overall-system-architecture.md) | Overall System Architecture | P0 | Proposed |
| [002](ADR-002-frontend-technology-and-ui-strategy.md) | Frontend Technology and UI Strategy | P0 | Proposed |
| [003](ADR-003-backend-architecture-with-net-10.md) | Backend Architecture with .NET 10 | P0 | Proposed |
| [004](ADR-004-microsoft-graph-integration-strategy.md) | Microsoft Graph Integration Strategy | P0 | Proposed |
| [005](ADR-005-microsoft-places-data-model-and-hierarchy.md) | Microsoft Places Data Model and Hierarchy | P0 | Proposed |
| [006](ADR-006-exchange-resource-mailboxes-as-parking-resources.md) | Exchange Resource Mailboxes as Parking Resources | P0 | Proposed |
| [007](ADR-007-parking-reservations-and-consistency.md) | Parking Reservations and Consistency | P0 | Proposed |
| [008](ADR-008-visitor-management-and-data-storage.md) | Visitor Management and Data Storage | P1 | Proposed |
| [009](ADR-009-authentication-and-authorization.md) | Authentication and Authorization | P0 | Proposed |
| [010](ADR-010-database-and-persistence-strategy.md) | Database and Persistence Strategy | P1 | Proposed |
| [011](ADR-011-synchronization-caching-and-data-refresh.md) | Synchronization, Caching and Data Refresh | P1 | Proposed |
| [012](ADR-012-error-handling-resilience-and-observability.md) | Error Handling, Resilience and Observability | P1 | Proposed |
| [013](ADR-013-deployment-and-hosting-strategy.md) | Deployment and Hosting Strategy | P1 | Proposed |
| [014](ADR-014-testing-strategy.md) | Testing Strategy | P1 | Proposed |
| [015](ADR-015-administrative-provisioning-and-privileged-operations.md) | Administrative Provisioning and Privileged Operations | P0 | Proposed |
| [016](ADR-016-github-actions-terraform-delivery.md) | GitHub Actions Terraform Delivery | P0 | Accepted |

## Review order
1. Application architecture: 001, 002, 003.
2. Microsoft 365 integration and permissions: 004, 005, 009, 015.
3. Domain and operations: 006, 007, 008, 010–014.
4. Delivery architecture: 016 (Accepted; its permission and production approval gates remain open).

Only ADR-016 is accepted. Do not infer acceptance of any other ADR from its dependencies or from supporting implementation work.
