# PlaceHub enterprise UI design system

**Status:** Implemented for the local offline POC. No architecture, identity or integration boundary changes.

## Structure

The Blazor server application keeps one shell (`MainLayout`) and one role-aware grouped navigation (`NavMenu`). Pages use global design tokens from `wwwroot/app.css`; no JavaScript framework, icon package or commercial component dependency was introduced. The stylesheet is referenced through Blazor static-asset fingerprinting so development and published output resolve the same asset.

Navigation groups are **Arbeitsplatz**, **Betrieb** and **Administration**. Administrative entries are hidden unless the synthetic POC actor has `SystemAdministrator`. This visibility is a usability control only; application services remain the authorization boundary.

## Design tokens and components

- Navy application chrome and neutral light content canvas.
- Indigo primary action, green success, amber pending and red error/reconciliation states.
- 8/12/16-pixel radii, restrained shadow, consistent inputs and compact tables.
- Shared `StatusBadge`; reusable surface, KPI, filter, empty-state and page-heading patterns.
- System fonts only. Unicode glyphs are decorative and hidden from assistive technology where appropriate.

## Responsive and accessible behavior

The layout collapses below 820 px into an explicit keyboard-operable sidebar toggle. KPI/filter/form grids reduce to two and then one column. Tables and calendar grids scroll horizontally rather than clipping operations. Interactive controls have visible `:focus-visible` treatment; semantic headings, labels, status regions and accessible names are included. Status badges combine text, shape and color. Reduced-motion preference disables transitions.

Implemented checks target WCAG 2.2 AA mechanics, but this is not a formal conformance audit. Color contrast, zoom, keyboard-only flows and screen-reader output require a dedicated browser/tool audit before market release.

## User journeys

1. Dashboard: select an authorized location and review explicitly sourced mock KPIs, capacity, bookings and warnings.
2. Booking calendar: switch location/resource type/time range; review distinct available, reserved and unknown offline states. It never confirms a real booking.
3. Desk pools: search and filter hierarchy/status, inspect summaries/details, submit create or capacity requests.
4. Parking: review features/status, open calendar, submit create, policy-change or reversible-disable requests.
5. Approvals: a PlaceHub administrator approves or rejects an immutable version and triggers only the offline typed worker.

## Local verification

```powershell
dotnet build src/PlaceHub.Web/PlaceHub.Web.csproj
dotnet test PlaceHub.slnx
pwsh -NoProfile -File tests/Test-UIStatic.ps1
dotnet publish src/PlaceHub.Web/PlaceHub.Web.csproj -c Release
```

The global search is visibly disabled because no approved search contract exists. Calendar booking buttons are disabled for non-available states, and available buttons do not claim external confirmation. Notifications are omitted because no notification state exists.

## Remaining UX gaps

- Replace Unicode navigation glyphs with a reviewed, accessible first-party SVG set if branding approves it.
- Add browser automation and automated accessibility scanning when a compatible local test tool is approved.
- Add durable SQLite workflow persistence before any restart-sensitive worker execution.
- Replace the synthetic role selector with real Entra authentication/assignment after its separate approval.
- Complete deep building, floor, desk, visitor and reservation pages after their proposed ADRs are accepted.
