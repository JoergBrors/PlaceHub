# Exchange provisioning certificate lifecycle runbook

**Status:** Draft operational design under proposed ADR-015; execution requires approved tenant, worker, application, permission and change record.

## Shared requirements

The service owner owns availability; security/PKI approves issuance/revocation; Entra administrators upload/remove public credentials; the worker operator validates runtime access; Exchange administrators validate effective authorization. Inventory contains environment, application reference, serial/thumbprint, issuer, CSP provider, key specification, validity, store/version reference, owner, ticket and last test—never PFX, password, private key or token.

Use RSA 2048-or-stronger, SHA-256, a supported legacy CSP and `AT_KEYEXCHANGE`; reject CNG/KSP certificates for this Exchange Online PowerShell CBA path. Upload only the public certificate to Entra. Development and production use separate applications, key pairs, stores and operators where policy requires.

## Initial local-PoC path: Windows certificate store

The first approved test-tenant proof runs as a dedicated Windows service account outside the web container. Enroll the CSP-backed certificate directly into that account's CurrentUser personal store where possible. Mark the private key non-exportable when the enrollment and rotation process does not require PFX transport. Exchange CBA through `Connect-ExchangeOnline -CertificateThumbprint` uses the installed private key and does not itself require exportability.

Private-key ACLs grant read/use only to the dedicated service account and authorized recovery operators. Interactive developers, the web/container identity, Docker engine guests and Terraform identity receive no access. Prohibit profile roaming, interactive sign-in for the service account, PowerShell transcription, process dumps and certificate-store mounts into containers.

If organizational PKI delivery requires a PFX, treat exportability as a temporary enrollment/transport concession: create it only in an approved workspace, protect it through the authorized transfer channel, import it with a non-exportable runtime key where supported, verify access, then destroy transport copies under the media-handling procedure. Never store PFX/passwords in Git, `.env`, Compose, CI artifacts or ordinary shared storage.

### Local enrollment and validation

1. Approve the exact environment, app, service account, provider, key length, lifetime and subject.
2. Enroll into the service-account store using the approved CSP/`AT_KEYEXCHANGE`; reject CNG/KSP.
3. Apply and verify private-key ACLs and non-exportability; record public metadata only.
4. Upload the public certificate to the matching Entra application under a separate administrator action.
5. Prove public-key equality, app-only authentication and allowlisted read-only Exchange command in the test tenant.
6. Prove that the web user, ordinary developer, Terraform identity and another service account cannot use/read the private key.

## Future Azure path: Key Vault and Managed Identity

This path is not part of the zero-incremental-cost PoC. It requires ADR-013/015 amendment, cost approval, a dedicated worker/runtime identity, one approved vault per environment, Azure RBAC, monitoring, soft delete and purge protection.

For `Connect-ExchangeOnline -Certificate <X509Certificate2>`, the future worker must retrieve the certificate's backing secret. That Key Vault certificate must therefore have an exportable RSA private key; a non-exportable Key Vault/HSM key cannot be substituted directly for this object-based flow. The runtime identity receives only the reviewed certificate/secret read role, never Key Vault Administrator. PFX bytes exist only in the isolated worker's process memory, are not written to disk, and are disposed with the Exchange session. Host administrators/process dumps remain a documented extraction risk.

## Monitoring and planned rotation

- Alert at 60, 30, 14 and 7 days before expiry and on unexpected Entra sign-ins, authentication failures, certificate-store/key ACL changes or—on the future path—Key Vault reads/version changes.
- Review credentials, owners, store ACLs and Exchange assignments quarterly.
- Treat an unexpected credential, private-key export, cross-environment use or missing owner/expiry as an incident.

Rotation procedure:

1. At least 60 days before expiry, enroll a new CSP RSA certificate using the selected path.
2. Add its public certificate to the same environment application without removing the old one.
3. Grant only the service account access to the new local key, or add the approved future vault version.
4. Select the new thumbprint/version explicitly and perform authentication plus read-only tests.
5. Run one separately approved synthetic verification and observe the stabilization window.
6. Remove the old Entra public credential, remove/disable the old local key or future vault version, verify old authentication fails and new succeeds, and close inventory/change records.

Before old-key removal, rollback may select the still-valid old certificate. Never use a client secret. If the old certificate is expired or suspected compromised, use emergency replacement instead.

## Emergency response

1. Stop/quarantine the worker and reject provisioning requests.
2. Remove the compromised public credential from Entra and deny access to the local key or disable the future vault version; revoke at the issuer when supported.
3. Review Entra sign-ins, Exchange audit, local security logs and PlaceHub correlations; on the future path include Key Vault audit.
4. Enroll a new key on a clean approved host and repeat access-denial and authentication tests.
5. Resume only after security acceptance; reconcile every operation from the exposure/outage window.

## Recovery exercises

Twice yearly in the test tenant, exercise expiry alert, overlap, rollback, emergency revocation, service-account/key ACL denial, worker rebuild and lost/corrupt store recovery. Future Key Vault exercises are added only after that path is approved. Evidence is sanitized and contains no private material.

## Official references

- [Exchange Online PowerShell app-only authentication](https://learn.microsoft.com/powershell/exchange/app-only-auth-powershell-v2)
- [`Connect-ExchangeOnline`](https://learn.microsoft.com/powershell/module/exchangepowershell/connect-exchangeonline)
- [Key Vault certificate exportability](https://learn.microsoft.com/azure/key-vault/certificates/about-certificates)
- [Export Key Vault certificates](https://learn.microsoft.com/azure/key-vault/certificates/how-to-export-certificate)

