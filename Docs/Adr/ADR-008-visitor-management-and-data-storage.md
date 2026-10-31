# ADR-008: Visitor Management and Data Storage

- **Status:** Proposed (nicht genehmigt)
- **Priority:** P1
- **Date:** 2026-10-31
- **Project:** PlaceHub – Workplace & Resource Management
- **Decision owner:** Noch festzulegen
- **Governance:** New ADR Required; vor Annahme bestehende Repository-ADRs prüfen

## Context
Physische Gäste sind nicht automatisch Entra-B2B-Gastkonten; nicht alle Besucherworkflows müssen in Microsoft Places abbildbar sein.

## Problem
Welche dauerhafte Architekturentscheidung wird für **Visitor Management and Data Storage** benötigt, ohne die Microsoft-365-Verantwortlichkeiten, Sicherheit oder Einfachheit des Systems zu gefährden?

## Proposed Decision
Wenn keine geeignete unterstützte Microsoft-Places-Integration verfügbar ist, lokale Visit- und Visitor-Daten für Termin, Host, Standort und Status speichern; keine automatische B2B-Gastanlage.

## Alternatives Considered
Native Places-Funktion (zuerst prüfen); lokale schlanke Verwaltung (Fallback); vollwertiges Visitor Management System (zu umfangreich).

## Rationale
Behält geschäftliche Kontrolle und minimiert Fremdabhängigkeiten.

## Consequences and Trade-offs
Eigenständige GDPR-Aufbewahrung, Löschfunktionen und ggf. Benachrichtigungen erforderlich.

## Security and Privacy Implications
Privacy by Design, minimale Datensätze, Aufbewahrungsfristen, Rolle/Standort, keine unnötige ID-Verifikation.

## Dependencies
ADR-009, ADR-010, ADR-012.

## Validation / Proof of Concept
Native Besucherfunktion, Datenschutzanforderungen und Check-in/out MVP-Relevanz klären.

## Proposed local PoC refinement (not approved)
Der lokale PoC verwendet ausschließlich eindeutig synthetische, wegwerfbare Besucherdaten in SQLite. Reale Besucher-, Mitarbeiter- oder andere personenbezogene Produktivdaten sind ausgeschlossen. Ob Visitor Management Bestandteil des initialen PoC sein muss sowie Retention, Rechtsgrundlage und Lösch-/Exportprozess bleiben fachliche und Datenschutz-Gates.

## Documentation Impact
Bei Freigabe Solution Architecture, Capability Matrix, Security-/Integration-Design, Betriebs- und Testdokumentation entsprechend aktualisieren. Konkrete Repository-Pfade vor Änderungen verifizieren.

## Open Questions / Approval Gates
- Gibt es bereits akzeptierte ADRs oder technische Vorgaben im Repository, die dieser Entscheidung widersprechen?
- Sind relevante Microsoft-365-Funktionen, API-Versionen, Berechtigungen und Lizenzbedingungen für den vorgesehenen Tenant geprüft?
- Ist der vorgeschlagene Umfang für das MVP angemessen?
- **Approval gate:** Entscheidung bleibt bis zur expliziten Architekturfreigabe `Proposed`.

## References
- Projektquelle: `PlaceHub_Project_Prompt.md` (vom Nutzer bereitgestellt; Anforderungen, ADR-Index und Zielarchitektur).

> Hinweis: Microsoft-Links sind Rechercheanker, keine Bestätigung aller API-Details. Unterstützungsstatus und Lizenzierung im Technical Discovery nachweisen.
