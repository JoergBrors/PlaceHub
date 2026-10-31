# Exchange provisioning certificate lifecycle runbook

**Status:** Draft; execution requires approved identity, worker, tenant, certificate authority/store and change record.

## Ownership and inventory

The certificate service owner owns availability; the security/PKI owner approves issuance and revocation; the Entra administrator uploads/removes public credentials; the worker operator validates runtime retrieval; the Exchange administrator validates app-only access. Separate production and development duties where policy requires.

Inventory records environment, application ID/object reference, certificate serial/thumbprint, issuer, CSP provider, key specification, `notBefore`/`notAfter`, Key Vault certificate and secret version or local store reference, owner, change ticket and last successful test. It never contains PFX bytes, password, private key, token or secret value.

## Enrollment

1. Open an approved change for the exact environment and `placehub-m365-provisioning-<environment>` application.
2. Generate/enroll RSA 2048-or-stronger using the approved legacy CSP and `AT_KEYEXCHANGE`; explicitly reject CNG/KSP output.
3. Mark the key exportable only because the Exchange module/Key Vault memory-loading design requires it. Restrict the enrollment workspace and remove temporary export files through the approved secure-media procedure.
4. Validate private-key presence, provider/type, key size, signature, dates and intended use offline. Never print private material.
5. Import PFX into the approved environment Key Vault as an exportable certificate, or into the ACL-restricted development service-account certificate store. Upload only the public certificate to the matching Entra application.
6. Verify public-key/thumbprint equality, inventory metadata and access-denial tests before enabling the version.

## Monitoring

- Alert certificate and backing-secret expiry at 60, 30, 14 and 7 days; page the owner at the final threshold.
- Monitor Key Vault read anomalies, disabled/deleted certificate versions, Entra service-principal sign-in failures, Exchange authentication failures and unexpected source hosts.
- Review current and previous credentials, owners, Key Vault/RBAC assignments and Exchange roles quarterly.
- Treat an unowned certificate, missing expiry, unexpected credential, cross-environment read or private-key export as a security incident.

## Planned rotation

1. At least 60 days before expiry, create a new CSP RSA key pair and certificate following enrollment.
2. Add the new public certificate to the same environment application without removing the old credential.
3. Add/import a new Key Vault certificate version or local-store certificate; never overwrite evidence of the previous version.
4. Configure the worker to select the explicitly approved new version, not merely “latest,” then execute authentication and read-only command tests.
5. Run one approved synthetic provisioning verification and confirm sanitized audit correlation.
6. Observe the approved stabilization window. Keep the old certificate enabled only for rollback and never beyond its expiry/policy limit.
7. Remove the old public credential from Entra, disable the old Key Vault version/store key, verify that old authentication fails and new authentication succeeds, then complete the inventory/change record.

## Failed rotation and rollback

Before old-credential removal, revert the worker's version selection to the old valid certificate, disconnect all Exchange sessions and investigate with sanitized evidence. Do not create a client secret. If the old certificate is expired or suspected compromised, rollback is prohibited; use emergency replacement.

## Emergency revocation/replacement

1. Stop or quarantine the worker and reject new provisioning requests.
2. Remove/disable the compromised public credential in Entra and disable its Key Vault/store version. Revoke through the issuer when supported.
3. Review Entra sign-ins, Key Vault access, Exchange audit and PlaceHub correlation records for the exposure window.
4. Enroll a new key pair on a clean approved host, upload/import through separated operators and rerun access-denial plus app-only authentication tests.
5. Resume only after the security owner accepts investigation findings and Exchange effective permissions are reconfirmed.
6. Reconcile all operations from the exposure/outage window; do not assume failed commands made no change.

## Process-memory handling

Retrieve the exportable PFX backing secret through the runtime managed identity, decode only in the isolated worker process and construct an ephemeral `X509Certificate2`. Do not use `PersistKeySet`, a PFX file, PowerShell transcription, a command-line password or environment variable. Pass the object directly to `Connect-ExchangeOnline -Certificate`; disconnect in `finally`, dispose certificate/key objects and terminate the short-lived process. Managed memory disposal reduces exposure but does not guarantee physical zeroization, so host isolation and dump prevention remain mandatory.

## Recovery exercises

Twice yearly in the test tenant, exercise expiry alert, planned overlap, rollback, compromised-key revocation, Key Vault denial/outage, deleted-version recovery within soft-delete retention and worker rebuild from pinned dependencies. Record only sanitized evidence and remediation actions.

