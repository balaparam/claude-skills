#!/usr/bin/env python3
"""
Selector Inspector — run this once to identify the correct field names
on your specific Odoo timesheet page. It opens a visible browser, logs in,
navigates to timesheets, clicks New, and prints all input field names/IDs.

Usage:
    ODOO_EMAIL=you@company.com ODOO_PASSWORD=secret python inspect_selectors.py
"""

import os
import sys

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    print("Run: pip install playwright && playwright install chromium")
    sys.exit(1)

URL = os.environ.get("ODOO_URL", "https://toco.tocumulus.ai")
EMAIL = os.environ.get("ODOO_EMAIL", "")
PASSWORD = os.environ.get("ODOO_PASSWORD", "")

if not EMAIL or not PASSWORD:
    print("Set ODOO_EMAIL and ODOO_PASSWORD environment variables.")
    sys.exit(1)

with sync_playwright() as pw:
    browser = pw.chromium.launch(headless=False)  # visible window
    page = browser.new_page(viewport={"width": 1440, "height": 900})
    page.goto(URL.rstrip("/") + "/odoo/timesheets", wait_until="networkidle")

    if "login" in page.url.lower():
        page.fill('input[name="login"]', EMAIL)
        page.fill('input[name="password"]', PASSWORD)
        page.click('button[type="submit"]')
        page.wait_for_url("**/odoo/**", timeout=20_000)

    page.goto(URL.rstrip("/") + "/odoo/timesheets", wait_until="networkidle")
    page.wait_for_timeout(1500)

    # Try to open new entry form
    for sel in ['button.o_list_button_add', 'button:has-text("New")', 'a:has-text("Add a line")']:
        btn = page.locator(sel).first
        if btn.is_visible():
            btn.click()
            break

    page.wait_for_timeout(1000)

    print("\n=== Visible INPUT fields on this page ===")
    inputs = page.locator("input:visible").all()
    for inp in inputs:
        name = inp.get_attribute("name") or ""
        id_ = inp.get_attribute("id") or ""
        placeholder = inp.get_attribute("placeholder") or ""
        val = inp.input_value() or ""
        print(f"  name={name!r:30} id={id_!r:30} placeholder={placeholder!r:30} value={val!r}")

    print("\n=== SELECT fields ===")
    selects = page.locator("select:visible").all()
    for sel in selects:
        name = sel.get_attribute("name") or ""
        print(f"  name={name!r}")

    print("\n=== Buttons ===")
    btns = page.locator("button:visible").all()
    for b in btns:
        print(f"  text={b.inner_text().strip()!r:40} class={b.get_attribute('class') or ''}")

    print("\nBrowser will stay open for 60 seconds so you can inspect manually…")
    page.wait_for_timeout(60_000)
    browser.close()
