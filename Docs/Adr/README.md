# PlaceHub – Architecture Decision Record Index

ADR status is recorded individually. On 2026-10-31 the Project Owner approved the local-first initial-PoC baseline in ADR-001, 002, 003, 009, 010, 012, 013 and 014. ADR-016 is accepted as amended: in-boundary create/update is normal automation, while delete/replacement/access removal requires exact-plan approval. ADR-004 through 008, ADR-011 and ADR-015 remain proposed.

| ADR | Title | Priority | Status |
|---|---|---|---|
| [001](ADR-001-overall-system-architecture.md) | Overall System Architecture | P0 | Accepted |
| [002](ADR-002-frontend-technology-and-ui-strategy.md) | Frontend Technology and UI Strategy | P0 | Accepted |
| [003](ADR-003-backend-architecture-with-net-10.md) | Backend Architecture with .NET 10 | P0 | Accepted |
| [004](ADR-004-microsoft-graph-integration-strategy.md) | Microsoft Graph Integration Strategy | P0 | Proposed |
| [005](ADR-005-microsoft-places-data-model-and-hierarchy.md) | Microsoft Places Data Model and Hierarchy | P0 | Proposed |
| [006](ADR-006-exchange-resource-mailboxes-as-parking-resources.md) | Exchange Resource Mailboxes as Parking Resources | P0 | Proposed |
| [007](ADR-007-parking-reservations-and-consistency.md) | Parking Reservations and Consistency | P0 | Proposed |
| [008](ADR-008-visitor-management-and-data-storage.md) | Visitor Management and Data Storage | P1 | Proposed |
| [009](ADR-009-authentication-and-authorization.md) | Authentication and Authorization | P0 | Accepted |
| [010](ADR-010-database-and-persistence-strategy.md) | Database and Persistence Strategy | P1 | Accepted |
| [011](ADR-011-synchronization-caching-and-data-refresh.md) | Synchronization, Caching and Data Refresh | P1 | Proposed |
| [012](ADR-012-error-handling-resilience-and-observability.md) | Error Handling, Resilience and Observability | P1 | Accepted |
| [013](ADR-013-deployment-and-hosting-strategy.md) | Deployment and Hosting Strategy | P1 | Accepted |
| [014](ADR-014-testing-strategy.md) | Testing Strategy | P1 | Accepted |
| [015](ADR-015-administrative-provisioning-and-privileged-operations.md) | Administrative Provisioning and Privileged Operations | P0 | Proposed |
| [016](ADR-016-github-actions-terraform-delivery.md) | GitHub Actions Terraform Delivery | P0 | Accepted (amended) |
| [017](ADR-017-durable-provisioning-queue-and-worker-contract.md) | Durable Provisioning Queue and Worker Contract | P0 | Proposed |

## Review order
1. Application architecture: 001, 002, 003.
2. Microsoft 365 integration and permissions: 004, 005, 009, 015.
3. Domain and operations: 006, 007, 008, 010–014.
4. Delivery architecture: 016 (Accepted as amended; destructive-plan retention, permission-policy and production gates remain open).

Acceptance is scope-specific and does not grant implementation authority, tenant permissions, consent, paid services or production deployment. Open decisions remain explicit in each ADR.
