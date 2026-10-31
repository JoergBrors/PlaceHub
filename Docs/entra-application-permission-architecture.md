# Entra application and permission architecture

**Status:** Draft for architecture and security approval; no registration, permission, consent, Exchange role, or credential is approved.

**Date:** 2026-10-31

## Decision summary

The proposed server-side Blazor Web App is one confidential web application. Use `placehub-frontend-development` for interactive sign-in and delegated Microsoft Graph calls. Do not create `placehub-backend-development` while UI and backend are one deployable process. Create it only after an approved split-hosted UI/API decision. Keep `placehub-m365-provisioning-development` isolated for explicitly approved unattended Microsoft 365 administration. The existing Terraform deployment application remains unchanged and receives no Graph or Exchange permission.

This design is compatible with the cost-constrained F1/SQLite development proposal: application registrations and consent do not require an Azure database. It does not authorize F1 hosting, SQLite, or any identity creation.

| Identity | Proposed type and use | Explicitly excluded |
|---|---|---|
| `placehub-frontend-development` | Single-tenant confidential Web app; OIDC authorization-code flow; interactive UI and approved delegated Graph calls. | Public-client and implicit flows; app-only provisioning; Terraform; tenant administration. |
| `placehub-backend-development` | Not created for the server-side monolith. Reserved name for a future independently hosted protected API. | Duplicate trust boundary or credentials in the current topology. |
| `placehub-m365-provisioning-development` | Single-tenant daemon identity; certificate or separately proven secretless workload credential; approved Graph/Exchange administration only. | Interactive sign-in, ordinary web requests, Terraform, broad Exchange administrator role. |
| Existing Terraform deployment app | ADR-016 delivery identity only. | Runtime, Microsoft Graph, Exchange and consent operations. |

## Registration and token flows

For `placehub-frontend-development`, configure the Web platform only. Use exact, approved redirect URIs such as `https://<approved-development-host>/signin-oidc` and a fixed local-development URI, plus the matching signed-out callback. Wildcards are forbidden. Disable implicit ID/access token issuance and public-client flows. Keep tokens server-side and use a secure, HTTP-only, same-site authentication cookie. Validate issuer, tenant, audience, nonce and state. Request only incremental scopes required by an enabled feature.

The browser authenticates to the confidential Blazor server through OIDC authorization code. The server calls Graph with the user's delegated token. It must authorize every operation from both an application role and a PlaceHub-owned location assignment; a role alone is insufficient. Proposed user-only app roles are `PlaceHub.OfficeManager`, `PlaceHub.LocationManager` and `PlaceHub.SystemAdministrator`. Their immutable role IDs must be generated once, committed as reviewed configuration and never regenerated during routine deployment.

If a separate UI/API is later approved, the frontend becomes an authorization-code-with-PKCE client and the backend exposes one narrow delegated scope. The API must validate its own audience and `scp`; Graph permissions are not accepted as permission to the PlaceHub API. On-Behalf-Of is allowed only after a use-case proof and consent review. This future option is not part of the current registration set.

The provisioning identity uses client credentials only in a controlled administrative worker or operator workflow. The web app never receives its credential or token. There is no token exchange between the Terraform identity, web identity and provisioning identity.

## Microsoft Graph permission inventory

Microsoft Graph has resource application ID `00000003-0000-0000-c000-000000000000`. IDs below are immutable permission identifiers from Microsoft's permissions reference. `openid`, `profile` and `offline_access` are OIDC protocol scopes and are not Graph application roles.

| Use case | Identity | Permission | Type / ID | Consent | Proposed disposition |
|---|---|---|---|---|---|
| Sign in; `/me` profile only if the application actually reads it | Web | `User.Read` | Delegated / `e1fe6dd8-ba31-4d61-89e7-88639da4683d` | User consent normally allowed; tenant policy can require admin | Optional; omit if token claims suffice. |
| List company places | Web | `Place.Read.All` | Delegated / `cb8f45a0-5c2e-4ea1-b803-84b870a7d7ec` | Admin required | Initial read candidate after ADR-004/005 approval. |
| Administer Places interactively | Web | `Place.ReadWrite.All` | Delegated / `4c06a06a-098a-4063-868e-5dfee3827264` | Admin required | Deferred; enable only with privileged UI approval. |
| Read basic calendar details/free-busy as signed-in user | Web | `Calendars.ReadBasic` | Delegated / `662d75ba-a364-42ad-adee-f5f880ea4878` | Admin not normally required | Candidate; validate the exact `getSchedule` operation in the test tenant. |
| Create/update/cancel the signed-in organizer's booking | Web | `Calendars.ReadWrite` | Delegated / `1ec239c2-d7c9-4623-a91a-a9775856bb36` | Admin not normally required | Candidate only after ADR-007 approval; Exchange resource processing remains authoritative. |
| Unattended Places inventory | Provisioning | `Place.Read.All` | Application / `913b9306-0ce1-42b8-9137-6a7df690a760` | Admin required | Deferred; use delegated read unless unattended inventory is proven necessary. |
| Unattended Places administration | Provisioning | `Place.ReadWrite.All` | Application / `f1f5e9aa-ad18-4b97-883e-6aa7e95b7a5f` | Admin required | Deferred and separately approved. |
| Unattended basic calendar read | Provisioning | `Calendars.ReadBasic.All` | Application / `8ba4a692-bc31-4128-9094-475872af8a53` | Admin required | Deferred; only with Exchange Application RBAC scope and test evidence. |
| Unattended calendar changes | Provisioning | `Calendars.ReadWrite` | Application / `ef54d2bf-783f-4e0f-bca1-3210c0444d99` | Admin required | Deferred; only if delegated booking cannot meet requirements and mailbox scope is proven. |

Microsoft's `getSchedule` operation page uses the label `Calendars.ReadBasic` for least-privileged application access, while the permissions reference exposes the application role as `Calendars.ReadBasic.All`. Do not configure app-only free/busy from the label alone. Resolve the role by immutable ID from the tenant service principal and prove the operation and scope in the test tenant.

No application permission is part of the initial interactive baseline. Graph application permissions are tenant-wide at consent time; Exchange scoping must be effective and negatively tested before calendar application roles are granted.

## Exchange Online authorization boundary

Prefer delegated booking: the signed-in organizer creates a normal calendar event inviting the resource mailbox, and Exchange accepts or declines it. Availability, acceptance and cancellation remain Exchange state, not SQLite state.

If app-only calendar access is approved, create an Exchange service-principal pointer and assign `Application Calendars.Read` or `Application Calendars.ReadWrite` through Exchange Application RBAC to a custom resource scope containing only development parking mailboxes. Use a stable, dedicated mailbox marker or direct membership in a dedicated mail-enabled security group; nested group membership is not an authorization assumption. Verify an allowed and a denied mailbox with `Test-ServicePrincipalAuthorization`.

Do not combine an unscoped Entra calendar application grant with a scoped Exchange assignment without proving the effective result. Grants are additive; an unscoped grant can defeat the intended boundary.

Mailbox provisioning and `Set-CalendarProcessing` require the Exchange management interface, not ordinary Graph calendar roles. If approved, `placehub-m365-provisioning-development` may receive Office 365 Exchange Online `Exchange.ManageAsApp` (`resourceAppId` `00000002-0000-0ff1-ce00-000000000000`, application role ID `dc50a0fb-09a3-484d-be87-e023b12c6440`) plus a custom Exchange RBAC role containing only the proven cmdlets and parameters. Discover the exact parent role and role entries read-only in the target tenant; do not assign Exchange Administrator. Candidate operations are constrained discovery, `New-Mailbox -Equipment`, required `Set-Mailbox` fields, and `Get/Set-CalendarProcessing` parameters.

There is an unresolved creation-scope problem: a new mailbox cannot match a marker-based scope until it exists and is marked. The approved design must either retain a human bootstrap step or explicitly approve a narrowly controlled wider creation scope. Organization-wide provisioning is not an implicit fallback. The newer Exchange Admin API documents `Exchange.ManageAsAppV2`; it is not substituted for the established PowerShell permission without a separately tested interface decision.

## Credentials, ownership and Terraform boundary

Prefer a managed identity plus federated identity credential for the confidential web client if the selected App Service/.NET library combination proves this path. Microsoft.Identity.Web documents certificateless credentials using managed identity and federation. Until that proof succeeds, no runtime credential is approved. Do not create a client secret. A certificate is the fallback only after ownership, secure storage, rotation, expiry alerting and recovery are approved.

The privileged provisioning identity should use a certificate with overlap rotation and emergency revocation, stored in an approved organizational certificate store. Do not place it in the F1 web app or repository. Azure Key Vault is not provisioned under the zero-new-paid-resource profile; selecting it requires a cost and hosting approval. Managed identity for Exchange automation must be assessed separately on a supported isolated compute host and does not justify running privileged administration in the web app.

The detailed certificate, Key Vault, worker and Exchange-management design is specified in [Exchange Online parking-resource provisioning architecture](exchange-provisioning-architecture.md) and its [certificate lifecycle runbook](exchange-certificate-lifecycle-runbook.md). It requires a CSP-backed exportable RSA private key for the supported Exchange Online PowerShell CBA path; CNG and client-secret fallbacks are prohibited.

Future Terraform may own application objects, service principals, redirect URIs, app roles, federated credentials and declared `required_resource_access` only after ADR-016's Entra-management gate is approved. It must not grant admin consent, Exchange role assignments, directory roles, mailbox scope membership or credentials. Those remain privileged, auditable operator procedures. Object owners must be named security groups, not the Terraform deployment service principal as a standing privileged owner, unless separately approved.

## Consent and change procedure

1. Approve ADR-002/004/005/006/007/009/013/015 decisions and the exact registration inventory.
2. Prove redirect URIs, hosting credential method, Graph operations, tenant licensing and Exchange scopes in a non-production tenant.
3. Review a manifest diff containing exact resource app IDs, permission IDs, app-role IDs and credential metadata; reject unexpected defaults such as unused `User.Read`.
4. A designated Entra/Exchange administrator grants only the approved consent and RBAC assignments outside the Terraform workflow. Record approver, ticket, tenant, app object IDs, permission IDs and expiry/review date without recording credential material.
5. Run positive and negative tests, capture sanitized evidence, and remove any permission whose feature is disabled or whose scope cannot be enforced.
6. Repeat the review for every new permission, redirect URI, credential, role or production environment. Consent in development never authorizes production.

## Negative authorization and least-privilege validation

| Test | Required result |
|---|---|
| Unauthenticated or wrong-tenant user | Sign-in/API denied. |
| Valid user with no PlaceHub role | Every protected use case denied server-side. |
| Role without location assignment | Cross-location read/write denied. |
| Office Manager invokes privileged provisioning | Denied; no provisioning token is available to the web process. |
| Token for Graph presented to a future PlaceHub API | Denied by audience validation. |
| Missing delegated scope or app role | Operation denied before Graph/Exchange call. |
| App-only calendar access to tagged development mailbox | Allowed only for the assigned Exchange application role. |
| App-only calendar access to untagged, user, or production mailbox | Denied and verified with Exchange authorization tooling plus an API probe. |
| Provisioning app attempts an unapproved cmdlet/parameter | Denied by custom Exchange RBAC. |
| Terraform identity requests Graph/Exchange token | No permission; denied. |
| Credential expired/revoked or certificate rotated | Fail closed; sanitized alert; documented recovery works. |

Quarterly and before production, enumerate effective Entra grants and Exchange assignments, compare immutable IDs to the approved manifest, test both sides of every resource scope, review sign-in/audit logs, rotate credentials, and remove unused permissions. Never log access tokens, assertions, certificates, consent responses, raw Graph/Exchange payloads or sensitive object identifiers.

## ADR impact and approval gates

No conflict with accepted ADR-016 was found, provided its deployment identity remains unchanged and consent stays outside Terraform delivery. ADR-002, ADR-004, ADR-005, ADR-006, ADR-007, ADR-009, ADR-013 and ADR-015 remain proposed. Their new notes are design input, not acceptance.

Provisioning must stop until the Project Owner and responsible security/Microsoft 365 authorities approve: the single-app Blazor topology; exact redirect URIs; application roles and location model; each exact Graph permission; delegated booking behavior; Exchange mailbox type, scope and custom management role; creation-scope solution; credential host/storage/rotation; whether Terraform manages Entra objects; admin consent; tenant licensing; and separate production registrations and controls.

## Official references

- [Microsoft Graph permissions reference](https://learn.microsoft.com/graph/permissions-reference?view=graph-rest-1.0)
- [List places](https://learn.microsoft.com/graph/api/place-list?view=graph-rest-1.0)
- [Get schedule](https://learn.microsoft.com/graph/api/calendar-getschedule?view=graph-rest-1.0)
- [Exchange Application RBAC](https://learn.microsoft.com/exchange/permissions-exo/application-rbac)
- [App-only Exchange Online PowerShell authentication](https://learn.microsoft.com/powershell/exchange/app-only-auth-powershell-v2)
- [Managed identity with Exchange Online PowerShell](https://learn.microsoft.com/powershell/exchange/connect-exo-powershell-managed-identity?view=exchange-ps)
- [Microsoft.Identity.Web credentials](https://learn.microsoft.com/entra/msidweb/authentication/credentials-overview)
- [Equipment mailboxes](https://learn.microsoft.com/exchange/recipients/equipment-mailboxes)
- [Find Exchange cmdlet permissions](https://learn.microsoft.com/powershell/exchange/find-exchange-cmdlet-permissions?view=exchange-ps)

