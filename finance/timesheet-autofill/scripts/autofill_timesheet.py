#!/usr/bin/env python3
"""
Odoo Timesheet Auto-Fill Script
Automatically fills in 8.0 hours on the Odoo timesheet for today (weekdays only).

Requirements:
    pip install playwright
    playwright install chromium

Environment Variables (required):
    ODOO_URL      - Base URL, e.g. https://toco.tocumulus.ai
    ODOO_EMAIL    - Login email
    ODOO_PASSWORD - Login password

Optional:
    ODOO_PROJECT  - Project name to select in dropdown (default: first available)
    ODOO_HOURS    - Hours to log (default: 8.0)
    ODOO_HEADLESS - Set to "false" to watch the browser (default: true)
"""

import os
import sys
import json
import logging
from datetime import date, datetime

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)


def is_weekday(d: date) -> bool:
    return d.weekday() < 5  # 0=Mon ... 4=Fri


def load_config() -> dict:
    cfg = {
        "url": os.environ.get("ODOO_URL", "https://toco.tocumulus.ai"),
        "email": os.environ.get("ODOO_EMAIL", ""),
        "password": os.environ.get("ODOO_PASSWORD", ""),
        "project": os.environ.get("ODOO_PROJECT", ""),
        "hours": float(os.environ.get("ODOO_HOURS", "8.0")),
        "headless": os.environ.get("ODOO_HEADLESS", "true").lower() != "false",
    }
    config_path = os.path.join(os.path.dirname(__file__), "..", "assets", "config.json")
    if os.path.exists(config_path):
        with open(config_path) as f:
            file_cfg = json.load(f)
        cfg.update({k: v for k, v in file_cfg.items() if v})
    if not cfg["email"] or not cfg["password"]:
        log.error("ODOO_EMAIL and ODOO_PASSWORD must be set (env vars or config.json).")
        sys.exit(1)
    return cfg


def run(cfg: dict):
    today = date.today()
    if not is_weekday(today):
        log.info("Today is %s (%s) — skipping (weekend).", today, today.strftime("%A"))
        return

    log.info("Running timesheet fill for %s (%s)", today, today.strftime("%A"))

    try:
        from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout
    except ImportError:
        log.error("playwright not installed. Run: pip install playwright && playwright install chromium")
        sys.exit(1)

    timesheet_url = cfg["url"].rstrip("/") + "/odoo/timesheets"

    with sync_playwright() as pw:
        browser = pw.chromium.launch(headless=cfg["headless"])
        ctx = browser.new_context(viewport={"width": 1440, "height": 900})
        page = ctx.new_page()

        # ── 1. Navigate & login ──────────────────────────────────────────────
        log.info("Opening %s", timesheet_url)
        page.goto(timesheet_url, wait_until="networkidle", timeout=30_000)

        if "/web/login" in page.url or "login" in page.url.lower():
            log.info("Login page detected — authenticating…")
            page.fill('input[name="login"], input[type="email"]', cfg["email"])
            page.fill('input[name="password"], input[type="password"]', cfg["password"])
            page.click('button[type="submit"], .btn-primary')
            page.wait_for_url("**/odoo/**", timeout=20_000)
            log.info("Logged in successfully.")

        # Re-navigate to timesheets in case login redirected elsewhere
        if "/odoo/timesheets" not in page.url:
            page.goto(timesheet_url, wait_until="networkidle", timeout=30_000)

        page.wait_for_timeout(1500)

        # ── 2. Detect view: list vs kanban vs grid ───────────────────────────
        # Try to click "New" button (list view) or "Add a line" (grid view)
        new_btn = page.locator(
            'button.o_list_button_add, '
            'button:has-text("New"), '
            'a:has-text("Add a line"), '
            'button:has-text("Add a line")'
        ).first

        try:
            new_btn.wait_for(state="visible", timeout=5_000)
            new_btn.click()
            log.info("Clicked 'New / Add a line' button.")
            page.wait_for_timeout(800)
        except PWTimeout:
            log.warning("No 'New' button found — the form may already be open or the view differs.")

        # ── 3. Set the date to today ─────────────────────────────────────────
        date_str = today.strftime("%m/%d/%Y")  # Odoo default locale MM/DD/YYYY
        date_field = page.locator(
            'input[name="date"], .o_field_date input, td.o_field_cell[name="date"] input'
        ).first
        try:
            date_field.wait_for(state="visible", timeout=4_000)
            date_field.triple_click()
            date_field.fill(date_str)
            date_field.press("Escape")  # close date picker
            log.info("Date set to %s", date_str)
        except PWTimeout:
            log.info("Date field not found or not editable (may be auto-set).")

        # ── 4. Select project from dropdown ─────────────────────────────────
        project_field = page.locator(
            'div[name="project_id"] input, '
            '.o_field_many2one[name="project_id"] input, '
            'td[name="project_id"] input'
        ).first
        try:
            project_field.wait_for(state="visible", timeout=5_000)
            project_field.click()
            page.wait_for_timeout(500)

            if cfg["project"]:
                project_field.fill(cfg["project"])
                page.wait_for_timeout(600)

            # Pick first option in dropdown
            dropdown_option = page.locator(
                '.o_dropdown_item, .dropdown-item, ul.ui-autocomplete li'
            ).first
            dropdown_option.wait_for(state="visible", timeout=5_000)
            option_text = dropdown_option.inner_text()
            dropdown_option.click()
            log.info("Selected project: %s", option_text.strip())
            page.wait_for_timeout(500)
        except PWTimeout:
            log.warning("Project dropdown not found or no options available.")

        # ── 5. Fill hours ────────────────────────────────────────────────────
        hours_str = str(cfg["hours"])
        hours_field = page.locator(
            'input[name="unit_amount"], '
            '.o_field_float[name="unit_amount"] input, '
            'td[name="unit_amount"] input, '
            'input[name="duration"]'
        ).first
        try:
            hours_field.wait_for(state="visible", timeout=5_000)
            hours_field.triple_click()
            hours_field.fill(hours_str)
            log.info("Hours set to %s", hours_str)
        except PWTimeout:
            log.error("Hours field not found — check selectors in this script.")
            _save_debug(page)
            browser.close()
            sys.exit(1)

        # ── 6. Save ──────────────────────────────────────────────────────────
        save_btn = page.locator(
            'button.o_form_button_save, '
            'button[name="save_manually"], '
            '.o_list_button_save, '
            'button:has-text("Save")'
        ).first
        try:
            save_btn.wait_for(state="visible", timeout=4_000)
            save_btn.click()
            log.info("Saved timesheet entry.")
        except PWTimeout:
            # Some Odoo views auto-save on blur — press Tab then check for success toast
            hours_field.press("Tab")
            page.wait_for_timeout(1000)
            log.info("No explicit Save button; triggered auto-save via Tab.")

        # ── 7. Verify success ────────────────────────────────────────────────
        page.wait_for_timeout(1500)
        toast = page.locator(
            '.o_notification_manager .o_notification, '
            '.toast, [role="alert"]'
        ).first
        try:
            toast.wait_for(state="visible", timeout=3_000)
            toast_text = toast.inner_text()
            if "error" in toast_text.lower():
                log.error("Odoo reported an error: %s", toast_text)
                _save_debug(page)
            else:
                log.info("Success toast: %s", toast_text.strip())
        except PWTimeout:
            log.info("No toast message detected — entry likely saved silently.")

        log.info("Done. %.1f hours logged for %s.", cfg["hours"], today)
        browser.close()


def _save_debug(page):
    path = f"/tmp/timesheet_debug_{datetime.now():%Y%m%d_%H%M%S}.png"
    page.screenshot(path=path)
    log.info("Debug screenshot saved to %s", path)


if __name__ == "__main__":
    run(load_config())
