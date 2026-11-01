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

## Accepted amendment (target architecture): mandatory requester/approver separation (2026-11-01)

**Status: ACCEPTED as target architecture (Project Owner, 2026-11-01).** Approval wording: "ADR-004, ADR-005, ADR-015 und ADR-017 als Zielarchitektur freigeben, ohne operative Rechtefreigabe". This accepts the design only. NOT approved and still gated separately: effective Graph or Exchange permissions and consent, Exchange RBAC assignment, Terraform declarations and apply, worker identity, certificate and Key Vault access, worker activation, automatic mailbox creation, the bootstrap manifest content and any tenant write.

Invariants for every privileged request kind and operation (Create, Update, ChangeCapacity, ChangeBookingPolicy, Disable, Reconcile, BootstrapBuilding and Places hierarchy writes):

1. Requester and approver are different immutable identities (`SELF_APPROVAL_DENIED`; identifier comparison is case-insensitive).
2. An unknown or empty identity fails closed (`IDENTITY_UNKNOWN`) for create, edit, approve and start.
3. Approval binds the exact request version and a SHA-256 digest of the typed payload; an edit clears the approval and only the requester may edit (`EDIT_OWNER_ONLY`).
4. `Start` and every worker call `VerifyApprovalIntegrity()` independently (approved state, approver != requester, version, digest) and fail with `APPROVAL_INTEGRITY_FAILED`.
5. A request runs once: a second start is rejected by state and version; a tampered payload cannot run.
6. Approval and start are location-bound; cross-location actors are denied.

Tests: `FourEyesApprovalTests` (all kinds and operations), `PlacesProvisioningTests`. No privileged live worker may run until these rules are accepted and proven in the target environment.
