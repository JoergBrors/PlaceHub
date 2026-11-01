# ADR-017: Durable Provisioning Queue and Worker Contract

- **Status:** Accepted for single-instance development
- **Priority:** P0
- **Date:** 2026-11-01
- **Project:** PlaceHub – Workplace & Resource Management
- **Approval date:** 2026-11-01
- **Decision authority:** Project Owner approval
- **Governance:** Development request/execution contract accepted; production persistence and live privileges remain gated

## Context

PlaceHub already models version-bound administrative requests and an offline mock execution in the web process. Phase 3 requires durable claims, leases, retries, heartbeats, reconciliation and a separately hosted privileged worker. ADR-010 permits disposable single-instance SQLite data, but does not decide queue concurrency or worker trust. ADR-015 remains proposed.

## Decision

For the local single-instance PoC, store business requests, immutable approved payload versions, technical executions, leases, attempts, heartbeats, notifications and sanitized audits in SQLite. Use transactional compare-and-set claims with one active lease per execution, bounded retries and explicit reconciliation. Keep business request state separate from technical execution state.

Run the worker as a separate .NET process using the same domain/application contracts. The mock worker has no tenant client or credential. A future live Windows worker uses a separate approved identity and certificate and never shares its credential with the web process. SQLite is not claimed to provide distributed-queue guarantees; multiple hosts and production persistence require an amendment.

## Required state and invariants

- Business: Draft, Submitted, AwaitingApproval, Approved, Rejected and outcome visibility.
- Execution: Queued, Claimed, Running, PendingExternalConfirmation, Succeeded, Failed and RequiresReconciliation.
- Approval binds exact request ID, version and immutable payload digest.
- One idempotency key maps to one logical operation; one non-expired lease may execute it.
- Lease expiry permits recovery, but an ambiguous external mutation goes to reconciliation rather than blind retry.
- Worker verifies environment, operation allowlist, location, naming, resource version and approval before execution.
- Web never executes PowerShell and never receives worker credentials or raw worker output.

## Alternatives

- In-memory execution: insufficient for restart recovery.
- Distributed broker: unnecessary and adds operations/cost for the local PoC.
- SQLite queue: minimal and consistent with ADR-010, with explicit single-instance limitations.
- Privileged execution in web: rejected by ADR-001/009 boundaries.

## Security and operational consequences

SQLite file access becomes security-sensitive. Claims require transactional tests, stale leases need deterministic recovery, and audit data must remain allowlisted. Production scale-out, HA, backup/RTO/RPO and provider migration remain undecided. Accepting this ADR does not approve Graph/Exchange permissions, consent, certificates, tenant mutation or a live worker.

## Approval gates

1. Project Owner accepts the request/execution split and SQLite single-instance limits.
2. Security accepts lease, retry, replay and ambiguous-result rules.
3. ADR-015 is accepted or amended for the isolated worker boundary.
4. Live-worker identity, Exchange RBAC, certificate lifecycle and operation allowlists are separately approved.
5. Production persistence requires a later amendment.

## References

- ADR-001, ADR-009, ADR-010, ADR-012, ADR-014 and proposed ADR-015.
- `../exchange-provisioning-architecture.md`
- `../ui-driven-resource-administration.md`
