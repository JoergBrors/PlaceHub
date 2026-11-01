# Live-first architecture approval package

**Status:** Proposed package; no ADR status is changed and no live activation is authorized.

## Conflict requiring Project Owner decision

The new product direction says normal execution is live-first and mocks exist only in isolated tests. Accepted ADR-009 and ADR-013, plus the accepted local-first baseline, currently make local mocks the default initial-PoC topology. Active permission declarations are also outside development policy `2026-10-31.1`. The requested target therefore requires explicit amendments before runtime defaults or active Terraform policy are changed.

## Requested decisions

1. **ADR-004:** accept Graph v1.0 Places reads and delegated getSchedule; decide whether delegated calendar writes enter scope.
2. **ADR-005:** accept native Places hierarchy and keep workspace mutation method unresolved until test-tenant evidence.
3. **ADR-006/007:** decide parking mailbox type and delegated booking semantics.
4. **ADR-009 amendment:** replace mock-default normal execution with fail-closed single-tenant OIDC/Graph live execution; keep an explicitly enabled synthetic profile for tests only.
5. **ADR-011:** accept on-demand reads, bounded retry and explicit unavailable/stale states.
6. **ADR-013 amendment:** define which local runtime is “normal”, its approved credential store, TLS and operational ownership without adding paid Azure resources.
7. **ADR-015/017:** accept isolated worker and durable queue contracts before implementation.
8. **ADR-016 permission-policy authorization:** approve exact proposed declarations, policy version and whether declaration updates require an additional approval despite being structurally non-destructive.

## Permission declaration proposal

The inactive manifest at `infrastructure/terraform/proposals/development-m365-permissions.json` records exact resource applications, immutable IDs and delegated/application types. It is deliberately outside the Terraform root configuration. Moving it into `entra-applications.tf` and active policy is a separate reviewed change after approval. Declaration does not grant consent, Exchange RBAC, directory role, app-role assignment or certificate.

## Exchange evidence decision

Microsoft currently documents `Exchange.ManageAsApp` for app-only Exchange Online PowerShell and also documents `Exchange.ManageAsAppV2` for the newer Exchange Online Admin API. PlaceHub must select the actual execution interface and verify the corresponding tenant service-principal role ID before configuration. The existing ID must not be silently replaced or combined with a broader permission.

## Approval record required

Record Project Owner, security and operations decisions with date, target tenant/environment, exact permission-manifest digest, credential strategy, consent authority, role-assignment manifest, Exchange RBAC scope, worker host and mailbox-create residual-risk disposition. Until then, normal runtime remains the accepted explicit OfflineMock PoC profile and live mode fails closed.
