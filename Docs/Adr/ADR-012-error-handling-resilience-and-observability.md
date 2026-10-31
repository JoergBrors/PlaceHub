# ADR-012: Error Handling, Resilience and Observability

- **Status:** Accepted
- **Priority:** P1
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Approval date:** 2026-10-31
- **Decision authority:** Project Owner approval
- **Governance:** Accepted for local PoC logging/resilience; production telemetry requires review

## Context
Microsoft APIs können throttlen, ausfallen oder unklare Buchungszustände hinterlassen.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Error Handling, Resilience and Observability** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Decision
Strukturierte Logs, Distributed Tracing/Correlation IDs, kontrollierte Retry- und Backoff-Regeln, nachvollziehbare Fachfehler und Statusreconciliation.

## Alternatives Considered
Ad-hoc Exceptions (ungenügend); umfassender Event Bus (unnötig); zentraler Resilience-Ansatz (vorgeschlagen).

## Rationale
Betrieb und Ursachenanalyse werden einfacher.

## Consequences and Trade-offs
Zusätzliche Logging-/Monitoring-Konfiguration, Redaktionsregeln und Retention.

## Security and Privacy Implications
Keine Tokens, Kalenderdetails oder Besucher-PII in Logs; Monitoring-Zugriff und Audit-Schutz.

### Accepted secure automation logging scope

Bootstrap and Terraform automation logs use an allowlist of stable status and failure-category codes. Command arguments, raw subprocess output, exception details, Terraform plans/state/outputs, access tokens and infrastructure identifiers must not enter routine logs. Diagnostic detail belongs in authoritative audit planes and may be accessed only through an authorized incident procedure. Redaction and masking are secondary controls.

### Accepted provisioning resilience boundary

Privileged provisioning uses an idempotent state machine, bounded read-after-write verification and reconciliation. Audit logs contain only correlation, operation type, approved logical resource reference, state, attempt and stable category—never PowerShell streams, commands, tokens, private-key material, secret references or mailbox/calendar content. Live Exchange execution remains gated by ADR-015.

### Accepted local PoC diagnostics scope

Der lokale PoC schreibt allowlist-basierte strukturierte Logs nach stdout/stderr mit kurzer lokaler Retention. Azure Monitor, Log Analytics und Application Insights werden nicht provisioniert. Optionale lokale Telemetrie bleibt loopback-gebunden und synthetisch. Secret-/PII-Canaries, SQLite-Fehler, Container-Neustart und Mock-API-Ausfälle gehören in die Tests.

## Dependencies
ADR-004, ADR-007, ADR-013.

## Validation / Proof of Concept
Throttling-, Timeout-, Doppelversuch- und API-Ausfalltests sowie SLOs definieren.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- Production SLOs, telemetry destination, retention and on-call ownership require separate approval.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
