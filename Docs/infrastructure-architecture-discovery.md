# Infrastructure architecture discovery

**Status:** Draft assessment; local-first PoC proposal. No hosting, identity, database, Microsoft 365 or production decision is accepted.

**Date:** 2026-10-31

## Repository inventory

The repository contains no application source project and no Terraform `resource` block. Terraform configures AzureRM/AzureAD providers, the OIDC/Entra-authenticated Azure Blob backend, tenant/subscription inputs, read-only client discovery and an identity consistency check. Bootstrap scripts manage the already-established delivery foundation outside Terraform. Local application work must neither duplicate nor modify it.

ADR-016 is the sole accepted architecture decision. It governs Terraform delivery, not application hosting, and does not conflict with a local PoC.

## Revised recommendation

The initial PoC uses local Docker Compose, one Linux-compatible .NET 10 Blazor modular-monolith image and SQLite with synthetic disposable data in a named volume. No Azure service or Terraform application resource is required. The detailed topology, security model, migration plan, verification and backlog are in [Local-first Docker PoC architecture](local-first-poc-architecture.md).

This supersedes the earlier F1 App Service PoC recommendation. App Service is retained only as a future, separately funded custom-container candidate. No free Azure tier is part of the initial PoC.

Identity boundaries are specified in [Entra application and permission architecture](entra-application-permission-architecture.md). Privileged Equipment Mailbox administration stays isolated under [Exchange provisioning architecture](exchange-provisioning-architecture.md) and the [certificate lifecycle runbook](exchange-certificate-lifecycle-runbook.md). The initial PoC mocks administration; any live test-tenant activity requires separate approval.

## Hosting comparison

| Criterion | Local Docker Compose | Azure App Service custom container | Dedicated on-premises host |
|---|---|---|---|
| Initial position | Proposed PoC host. | Future funded option only. | Worker/extended-hosting candidate. |
| Azure cost | Zero incremental Azure cost; existing ADR-016 state charges remain. | Paid plan/registry/network/monitoring may apply. | No new Azure cost; organizational compute and labor remain. |
| Persistence | Named-volume SQLite, synthetic/disposable, one instance. | SQLite not approved for scale/production; persistence needs explicit design. | Local storage or approved internally operated database. |
| Identity | Exact localhost OIDC; no managed identity. | Managed identity possible after approval. | Internally operated certificate/workload identity. |
| Privileged worker | Separate local process first; never web container. | Separate approved compute required. | Hardened Windows worker preferred for first CBA proof. |
| Operations | Developer-host lifecycle; no SLA. | Managed platform features depend on paid tier. | Internal patching, backup, monitoring and on-call. |
| Migration | Establish portable image/configuration contracts. | Image may be reusable after proof; Compose/data/secrets do not migrate. | Same image or separately approved IIS model. |

Kubernetes is excluded without demonstrated orchestration requirements.

## Persistence boundary

SQLite is only the PoC provider. It holds PlaceHub-owned synthetic metadata, settings, correlation/idempotency and audit-shaped test records—not authoritative Places, Exchange availability/bookings, production visitors or sensitive records. EF Core migrations run through a controlled one-shot operation. The database may be discarded and rebuilt.

SQL Server versus PostgreSQL remains the production ADR-010 decision. Moving away from SQLite requires explicit schema/type/concurrency migration, transformation and rehearsed cutover; a Docker volume cannot be copied to App Service as an architecture migration.

## Identity, network and configuration

- Bind local web ingress to loopback and use a fixed HTTPS localhost URI registered exactly in Entra.
- Default Microsoft 365 adapters to mocks. Approved Graph tests use delegated least privilege in the test tenant.
- Keep tokens server-side and enforce application role plus location authorization.
- Never mount the Docker socket, host certificate store or Exchange certificate into the web container.
- Run ExchangeOnlineManagement only in the approved separate worker; evaluate a local Windows process before Linux containerization.
- Keep secrets outside Git, image layers, Compose, environment dumps and logs.
- No VNet, private endpoint, Azure DNS, database, compute or cloud monitoring is needed.

## Zero-incremental-Azure-cost boundary

The initial PoC must not provision App Service, ACR, Functions, Container Apps, Key Vault, Azure SQL/PostgreSQL, Monitor/Log Analytics/Application Insights, VNet/private endpoint, VM/managed compute, application Storage or another Azure resource. Terraform apply is not a local setup step and new application `resource` blocks are prohibited for this phase.

Existing remote-state storage and delivery identity remain unchanged. Their already-incurred storage/transaction cost is outside the incremental PoC budget and does not disappear. An absolute zero total Azure bill is not claimed.

## Revised roadmap

1. Approve proposed application, Blazor, backend, identity, SQLite, logging, hosting, testing and privileged-worker ADR refinements.
2. Implement module skeleton and secure multi-stage image in a separately authorized task.
3. Add hardened Compose, named-volume SQLite, controlled migrations and synthetic seed/reset.
4. Add configuration, secret-provider, runtime-identity and database abstractions without Azure dependencies in core layers.
5. Add safe local telemetry, health/readiness, image/SBOM scanning and offline mocks.
6. Separately approve exact local Entra callback and least-privilege test-tenant Graph validation.
7. Separately prove the Windows Exchange worker; evaluate a Linux container only after compatibility evidence.
8. Before funded cloud work, approve host, registry, database, secrets, identity, network, monitoring, cost and application-delivery design.
9. Rehearse database/identity/configuration migration; never treat the Compose volume or certificate store as portable state.
10. Retain ADR-016 manual OIDC/exact-plan controls for future Terraform with a separate application-delivery workflow decision.

## Approval gates

- Local Docker host and security assumptions.
- Exact HTTPS ports/callbacks and Entra change.
- Synthetic-only data classification and SQLite lifecycle.
- Base image, dependency pinning, vulnerability policy and provenance.
- Local secret storage and diagnostic retention.
- Any test-tenant Graph/Exchange permission or mutation.
- Worker host, certificate store and Exchange RBAC.
- Any paid Azure resource or future cloud deployment.
- Production database, SLO/RTO/RPO, privacy and operational ownership.

