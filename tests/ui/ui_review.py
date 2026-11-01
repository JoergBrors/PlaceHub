"""Renders the PlaceHub pages in a real browser (Microsoft Edge via Playwright) and records reproducible evidence.

Scope: the explicit synthetic test profile (no sign-in) plus the unauthenticated redirect of the live profile.
Authenticated live pages need a real Entra sign-in and are NOT covered here; they must be reviewed by a person.
Exit code 0 only if every page answered 200 without console errors, failed requests or an error page.
"""
import argparse, io, json, os, sys, uuid
from playwright.sync_api import sync_playwright

PAGES = [
    ("dashboard", "/"), ("places-verwaltung", "/places-verwaltung"), ("parkplaetze-verfuegbarkeit", "/parkplaetze"),
    ("parkplatz-verwaltung", "/parkplatz-verwaltung"), ("parkplatz-reservierungen", "/parkplatz-reservierungen"),
    ("buchungskalender", "/buchungskalender"), ("freigaben", "/freigaben"), ("provisionierung", "/provisionierung"),
    ("meine-auftraege", "/meine-auftraege"), ("gebaeude", "/gebaeude"), ("diagnose", "/diagnose"), ("fehlerseite", "/Error"),
]

parser = argparse.ArgumentParser()
parser.add_argument("--synthetic", default="https://localhost:3243")
parser.add_argument("--live", default="https://localhost:3242")
parser.add_argument("--out", required=True)
args = parser.parse_args()
os.makedirs(args.out, exist_ok=True)
report, failures = [], []

with sync_playwright() as p:
    browser = p.chromium.launch(channel="msedge", headless=True)
    ctx = browser.new_context(ignore_https_errors=True, viewport={"width": 1440, "height": 900}, locale="de-DE")
    for name, path in PAGES:
        page = ctx.new_page(); errors, failed = [], []
        page.on("console", lambda m, e=errors: e.append(m.text) if m.type == "error" else None)
        page.on("pageerror", lambda x, e=errors: e.append("pageerror: " + str(x)))
        page.on("requestfailed", lambda r, f=failed: f.append(r.url))
        try:
            resp = page.goto(args.synthetic + path, wait_until="networkidle", timeout=30000); status = resp.status if resp else None
        except Exception as ex:  # HTTP failure codes surface as navigation errors
            status = "NAVIGATION_ERROR: " + str(ex).splitlines()[0][:120]
        page.wait_for_timeout(1200)
        text = page.inner_text("body") if status == 200 else ""
        entry = {"page": name, "path": path, "status": status, "h1": page.locator("h1").first.inner_text() if page.locator("h1").count() else "",
                 "console_errors": errors[:5], "failed_requests": failed[:5], "chars": len(text)}
        page.screenshot(path=os.path.join(args.out, name + ".png"), full_page=True)
        if status != 200 or errors or failed or "Es ist ein Fehler aufgetreten" in text and name != "fehlerseite": failures.append(name)
        report.append(entry); page.close()

    page = ctx.new_page(); page.goto(args.synthetic + "/parkplatz-reservierungen", wait_until="networkidle"); page.wait_for_timeout(1200)
    button = page.get_by_role("button", name="Reservierung anfragen")
    disabled = button.is_disabled() if button.count() else None
    gate_text = "nicht aktiviert" in page.inner_text("body")
    report.append({"check": "reservation form locked while booking gates are closed", "submit_disabled": disabled, "gate_notice_shown": gate_text})
    if not (disabled and gate_text): failures.append("reservation-gate")

    # interactivity: the Blazor circuit must be live (a static prerender would ignore the click)
    page = ctx.new_page(); page.goto(args.synthetic + "/parkplatz-verwaltung", wait_until="networkidle"); page.wait_for_timeout(1500)
    page.get_by_label("Postfachadresse").fill("ph-ui-" + uuid.uuid4().hex[:8] + "@contoso.example"); page.get_by_label("Anzeigename").fill("Parkplatz 01")
    page.get_by_role("button", name="Registrierung beantragen").click(); page.wait_for_timeout(1500)
    interactive = "wartet auf Freigabe" in page.inner_text("body")
    report.append({"check": "parking registration form submits through the live Blazor circuit", "request_submitted_message": interactive})
    if not interactive: failures.append("blazor-interactivity")
    bad = ctx.new_page(); bad.goto(args.synthetic + "/parkplatz-verwaltung", wait_until="networkidle"); bad.wait_for_timeout(1500)
    bad.get_by_label("Postfachadresse").fill("not-an-address"); bad.get_by_label("Anzeigename").fill("X")
    bad.get_by_role("button", name="Registrierung beantragen").click(); bad.wait_for_timeout(1500)
    friendly = "Postfachadresse ist ungültig" in bad.inner_text("body") and "ValidationException" not in bad.inner_text("body")
    report.append({"check": "invalid input shows a friendly message without raw exception text", "friendly": friendly})
    if not friendly: failures.append("validation-message")

    page = ctx.new_page(); page.goto(args.synthetic + "/places-verwaltung", wait_until="networkidle"); page.wait_for_timeout(1200)
    body = page.inner_text("body")
    report.append({"check": "places page states write access is locked", "locked_notice": "Schreibzugriff gesperrt" in body or "nicht aktiviert" in body})

    live = ctx.new_page(); live.goto(args.live + "/", wait_until="domcontentloaded", timeout=30000); live.wait_for_timeout(1500)
    entra = "login.microsoftonline.com" in live.url
    report.append({"check": "live profile redirects unauthenticated users to Entra sign-in", "redirected": entra, "host": live.url.split("/")[2]})
    live.screenshot(path=os.path.join(args.out, "live-unauthenticated.png"))
    if not entra: failures.append("live-redirect")
    browser.close()

io.open(os.path.join(args.out, "ui-review.json"), "w", encoding="utf-8").write(json.dumps({"failures": failures, "results": report}, indent=2, ensure_ascii=False))
for e in report:
    print(e if "page" not in e else f"{e['page']:28} http={e['status']} h1='{e['h1']}' errors={len(e['console_errors'])} failed={len(e['failed_requests'])}")
print("UI_REVIEW_FAILURES:", failures or "none")
sys.exit(1 if failures else 0)
