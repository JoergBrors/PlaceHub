# Microsoft 365 read-only readiness

**Status:** Real OIDC and delegated Graph implementation complete; effective consent, client-certificate registration, role/location assignments and tenant API evidence remain activation gates.

## Architecture and mode boundary

`Microsoft365:Mode` accepts `Microsoft365ReadOnly` as the checked-in fail-closed normal default. `OfflineMock` is available only through the explicit `SyntheticTest` profile. Offline adapters contain no HTTP client and return deterministic synthetic records. Read-only adapters use only the allowlisted Microsoft Graph v1.0 Places GET endpoints and `POST /me/calendar/getSchedule`, whose POST semantics are read-only. No create, update, delete, event or booking-policy endpoint exists in the adapter contracts.

`Microsoft365ReadOnly` fails at startup unless tenant/client identifiers and the configured client certificate exist. A mock identity is independently rejected by live authorization before token acquisition. OIDC requires the exact tenant, an authenticated principal, exactly one allowlisted PlaceHub app role and one or more server-side location assignments. Live errors never fall back to mock data.

The web app uses `Microsoft.Identity.Web` authorization-code flow, secure cookie authentication and an in-memory development token cache. The local process reads a passwordless `client-auth.pfx` from the existing read-only TLS directory mount; it has no Key Vault, Exchange or provisioning credential. `scripts/Initialize-LocalEntraCertificate.ps1` creates the local private PFX and a public `client-auth.cer` without overwriting files. Registration of that public certificate in Entra remains a separately approved operation. Exact callbacks are `https://localhost:3242/signin-oidc` and `https://localhost:3242/signout-callback-oidc`; the existing `8443` sign-in redirect is preserved for compatibility.

## Verified v1.0 capability matrix

| Capability | Endpoint | Query/paging | Least delegated permission | Evidence / limitation | Status |
|---|---|---|---|---|---|
| Buildings | `GET /v1.0/places/microsoft.graph.building` | `$select`, `$top`, `$skip`; default up to 1,000 | `Place.Read.All` | `resourceLinks` should be excluded when not needed | Adapter + fake HTTP tests |
| Floors | `GET /v1.0/places/microsoft.graph.floor` | same; default up to 1,000 | `Place.Read.All` | parent is a building | Adapter + tests |
| Sections | `GET /v1.0/places/microsoft.graph.section` | same; default up to 1,000 | `Place.Read.All` | parent is a floor | Adapter + tests |
| Desks | `GET /v1.0/places/microsoft.graph.desk` | same; default up to 1,000 | `Place.Read.All` | must belong to a section; mailbox may be absent | Adapter + tests |
| Workspaces | `GET /v1.0/places/microsoft.graph.workspace` | `$select/$top/$skip`, plus supported `$filter/$count`; default 100 | `Place.Read.All` | parent section, capacity/email may be unavailable | Adapter + tests |
| Descendants | `GET /v1.0/places/{id}/descendants/{placeType}` | hard maximum 2,500 results | `Place.Read.All` | tenant Places settings must be enabled | Documented; adapter currently uses typed lists and parent IDs |
| Free/busy | `POST /v1.0/me/calendar/getSchedule` | max interval/entry constraints; explicit Windows time zone | `Calendars.ReadBasic` | returns schedule availability; never reserves | Adapter + tests |

List/descendant APIs return nothing until the Microsoft Places tenant prerequisites are configured, including enabled buildings. Availability can return an Exchange `5006` condition for more than 1,000 calendar entries in a slot. The implementation exposes stable sanitized categories rather than raw payloads.

## Permission and approval matrix

Microsoft Graph resource app ID is `00000003-0000-0000-c000-000000000000`.

| Use case | Operation | Permission / immutable delegated ID | Consent | Resource/app authorization | ADR / approval |
|---|---|---|---|---|---|
| Optional profile | OIDC claims or `GET /me` if proven necessary | `User.Read` / `e1fe6dd8-ba31-4d61-89e7-88639da4683d` | normally user; tenant policy may differ | valid tenant/audience; app role | Proposed; not declared or approved |
| Places hierarchy | typed Places list/descendants | `Place.Read.All` / `cb8f45a0-5c2e-4ea1-b803-84b870a7d7ec` | admin required | PlaceHub role plus assigned building/location | Declared in Terraform; not consented/applied by this change |
| Free/busy | `POST /me/calendar/getSchedule` | `Calendars.ReadBasic` / `662d75ba-a364-42ad-adee-f5f880ea4878` | normally no admin; tenant policy may differ | PlaceHub role, location and explicit mailbox allowlist | Declared in Terraform; not consented/applied by this change |
| Places administration | write endpoints | `Place.ReadWrite.All` / `4c06a06a-098a-4063-868e-5dfee3827264` | admin required plus documented Places/Exchange roles | privileged workflow | Deferred and prohibited in this phase |
| Booking/cancel | calendar event write | `Calendars.ReadWrite` / `1ec239c2-d7c9-4623-a91a-a9775856bb36` | tenant policy dependent | organizer/resource policy | Deferred and prohibited in this phase |

The Terraform application and classifier policy now contain exactly the two delegated read scopes. No grant, consent, credential, role assignment or write permission resource was added. Declaration is not consent; consent is not proof that a token contains the delegated scope; a broad Graph scope does not replace PlaceHub location authorization. ADR-016 still requires a reviewed plan and separately authorized exact-plan apply.

## Runtime authorization mapping

Enterprise Application assignments supply exactly one `roles` claim from `PlaceHub.OfficeManager`, `PlaceHub.LocationManager` or `PlaceHub.SystemAdministrator`. Location scope is separately configured server-side using `PlaceHub__LocationAssignments__{object-id}__0={exact-place-id}`. Missing, malformed or empty mappings fail with `LOCATION_ASSIGNMENT_MISSING`; they never expand to all locations. The configured object IDs belong in protected deployment configuration, not source control.

The token provider validates tenant, signed-in object, Microsoft Graph audience and effective `scp` values after Microsoft.Identity.Web acquires the delegated token. The UI reports Graph connectivity only after a successful API response. Configuration values cannot mark consent or tenant capability as verified.

## Reliability and security controls

- Only HTTPS `graph.microsoft.com/v1.0/places/...` continuation links are accepted; cross-host/version links fail closed.
- Paging is capped at 25 pages per typed query.
- HTTP 429 and 503 retry at most three times and honor bounded `Retry-After`; other failures do not retry.
- Cancellation reaches token, HTTP, response stream and retry delay.
- Places are filtered to assigned building IDs and descendants after parsing; unauthorized tenant locations are not returned to UI.
- Availability validates interval, time zone, mailbox syntax/count and explicit mailbox authorization before HTTP.
- Only `availabilityView` and `scheduleId` are mapped; appointment subjects/details are not requested or retained.
- Tokens, claims, raw Graph payloads, mail/calendar content and exception details are never logged by these adapters.

## Readiness tool

`scripts/Test-Microsoft365Readiness.ps1` defaults to local repository inspection and performs no network call. It verifies exact callbacks, the exact two-scope Terraform declaration, the Live-First default and isolated SyntheticTest profile. Optional tenant inspection requires both `-InspectTenant` and `-ApproveReadOnlyTenantInspection`, exact tenant/application GUIDs, existing Azure CLI authentication and tenant match. It performs only a constrained Graph GET and never infers consent from declaration.

## Recorded ADR scope

- **ADR-004:** approve v1.0 typed Places reads and delegated getSchedule behind ports; prohibit silent mock fallback and all writes in read-only mode.
- **ADR-005:** approve native Place IDs/parent IDs as the hierarchy and unknown/null workspace properties rather than inferred values.
- **ADR-007:** approve free/busy as advisory only; it is not a reservation and exposes no appointment details.
- **ADR-011:** approve on-demand read with visible source/timestamp and authorization-aware short cache only after TTL/invalidation evidence. This implementation adds no live cache.
- **ADR-009:** no model change; tenant, app role, location, delegated scope, operation and resource checks remain cumulative.

## Activation gates

1. Review the exact Terraform update and authorize an ADR-016 `plan`; authorize `apply` separately only after the classifier reports an allowed non-destructive change.
2. Register the generated public `client-auth.cer` on the existing web application through a separately approved credential operation and define rotation/expiry ownership.
3. Obtain administrator consent for `Place.Read.All`; verify tenant policy for `Calendars.ReadBasic` and record the effective grant.
4. Populate `development-app-role-assignments.json` with explicitly approved user/group object IDs, approve the effective Enterprise Application assignments separately, and configure exact location mappings.
5. Verify Places licensing/settings and typed list behavior in the development tenant.
6. Perform real sign-in, token, Places and getSchedule tests. Only those successful API calls may change runtime status to connected.
7. Keep provisioning identity, write scopes, Exchange operations and production activation outside this read-only approval.

## Official Microsoft evidence

- [List place objects](https://learn.microsoft.com/graph/api/place-list?view=graph-rest-1.0)
- [Place descendants](https://learn.microsoft.com/graph/api/place-descendants?view=graph-rest-1.0)
- [Places API overview and prerequisites](https://learn.microsoft.com/graph/api/resources/places-api-overview?view=graph-rest-1.0)
- [Calendar getSchedule](https://learn.microsoft.com/graph/api/calendar-getschedule?view=graph-rest-1.0)
- [Microsoft Graph permission reference](https://learn.microsoft.com/graph/permissions-reference?view=graph-rest-1.0)
- [ASP.NET Core confidential OIDC web authentication](https://learn.microsoft.com/aspnet/core/security/authentication/configure-oidc-web-authentication?view=aspnetcore-10.0)
