# Architecture dependency matrix

| Capability | Accepted architecture | Remaining execution/security gates |
|---|---|---|
| Normal runtime | Live-First, fail closed | Tenant, confidential credential, declarations, consent, assignments, location records |
| Synthetic mocks | Explicit tests only | Must never combine with live identity/configuration |
| Places reads | Graph v1.0 native hierarchy | `Place.Read.All` declaration/consent and tenant evidence |
| Availability | Graph `getSchedule`, advisory only | `Calendars.ReadBasic` declaration/consent and mailbox authorization |
| Booking writes | Not accepted | ADR-007 write decision and `Calendars.ReadWrite` approval |
| Parking mailbox model | Not selected | ADR-006 Equipment/Room and mailbox-create risk decision |
| Worker | Isolated process | Host, identity, certificate, Exchange RBAC and operation allowlist |
| Worker interface | Exchange Online PowerShell | Exact module/cmdlet/parameter/RBAC evidence |
| Queue | SQLite single-instance development | Migration, lease/retry tests; no production data |
| Key Vault | Dedicated development worker-only vault | Exact name/RG/network/principal/cost and apply authorization |
| Terraform delivery | ADR-016 exact saved plan | Policy expansion, plan validation; unknown/destructive blocked |
| Production | Not approved | Data protection, hosting, persistence, operations and security sign-off |

