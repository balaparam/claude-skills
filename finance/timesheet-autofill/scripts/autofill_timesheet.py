#!/usr/bin/env python3
"""
Odoo Timesheet Auto-Fill — uses Odoo JSON-RPC API directly (no browser needed).
Logs 8.0 hours for today on weekdays only.

Config: assets/config.json  OR  environment variables:
  ODOO_URL, ODOO_EMAIL, ODOO_PASSWORD, ODOO_PROJECT, ODOO_HOURS
"""

import json
import os
import sys
import logging
import urllib.request
import urllib.error
from datetime import date

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)


def load_config() -> dict:
    cfg = {
        "url": os.environ.get("ODOO_URL", "https://toco.tocumulus.ai"),
        "email": os.environ.get("ODOO_EMAIL", ""),
        "password": os.environ.get("ODOO_PASSWORD", ""),
        "project": os.environ.get("ODOO_PROJECT", ""),
        "hours": float(os.environ.get("ODOO_HOURS", "8.0")),
    }
    config_path = os.path.join(os.path.dirname(__file__), "..", "assets", "config.json")
    if os.path.exists(config_path):
        with open(config_path) as f:
            file_cfg = json.load(f)
        cfg.update({k: v for k, v in file_cfg.items() if v})
    if not cfg["email"] or not cfg["password"]:
        log.error("ODOO_EMAIL and ODOO_PASSWORD must be set.")
        sys.exit(1)
    return cfg


def rpc(url: str, endpoint: str, payload: dict, session_id: str = "") -> dict:
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        url.rstrip("/") + endpoint,
        data=data,
        headers={
            "Content-Type": "application/json",
            "Cookie": f"session_id={session_id}" if session_id else "",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = json.loads(resp.read())
            # Grab set-cookie session_id if present
            raw_cookie = resp.headers.get("Set-Cookie", "")
            new_sid = ""
            for part in raw_cookie.split(";"):
                part = part.strip()
                if part.startswith("session_id="):
                    new_sid = part.split("=", 1)[1]
            return body, new_sid
    except urllib.error.HTTPError as e:
        log.error("HTTP %s: %s", e.code, e.read().decode())
        sys.exit(1)


def call_kw(base_url: str, sid: str, model: str, method: str, args=None, kwargs=None):
    payload = {
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
            "model": model,
            "method": method,
            "args": args or [],
            "kwargs": kwargs or {},
        },
    }
    result, _ = rpc(base_url, "/web/dataset/call_kw", payload, sid)
    if "error" in result:
        log.error("RPC error: %s", result["error"].get("data", {}).get("message", result["error"]))
        sys.exit(1)
    return result["result"]


def run(cfg: dict):
    today = date.today()
    if today.weekday() >= 5:
        log.info("Today is %s — skipping (weekend).", today.strftime("%A %Y-%m-%d"))
        return

    log.info("Filling timesheet for %s (%s)", today, today.strftime("%A"))
    base = cfg["url"].rstrip("/")

    # ── 1. Authenticate ──────────────────────────────────────────────────────
    log.info("Authenticating as %s …", cfg["email"])
    auth_payload = {
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
            "db": False,        # Odoo 17+ auto-detects db
            "login": cfg["email"],
            "password": cfg["password"],
        },
    }
    auth_result, sid = rpc(base, "/web/session/authenticate", auth_payload)

    if "error" in auth_result:
        log.error("Auth failed: %s", auth_result["error"])
        sys.exit(1)

    uid = auth_result.get("result", {}).get("uid")
    if not uid:
        # Try fetching uid via session info
        info, _ = rpc(base, "/web/session/get_session_info", {"jsonrpc": "2.0", "method": "call", "params": {}}, sid)
        uid = info.get("result", {}).get("uid")

    if not uid:
        log.error("Login failed — check your email and password.")
        sys.exit(1)

    log.info("Logged in (uid=%s)", uid)

    # ── 2. Find project ──────────────────────────────────────────────────────
    project_name = cfg.get("project", "")
    domain = [["name", "ilike", project_name]] if project_name else []
    projects = call_kw(base, sid, "project.project", "search_read",
                       args=[domain], kwargs={"fields": ["id", "name"], "limit": 5})

    if not projects:
        log.error("No project found matching '%s'. Check ODOO_PROJECT value.", project_name)
        sys.exit(1)

    project = projects[0]
    log.info("Using project: %s (id=%s)", project["name"], project["id"])

    # ── 3. Check if entry already exists for today ───────────────────────────
    existing = call_kw(base, sid, "account.analytic.line", "search_read",
                       args=[[["date", "=", str(today)],
                               ["project_id", "=", project["id"]]]],
                       kwargs={"fields": ["id", "unit_amount"], "limit": 1})

    if existing:
        entry = existing[0]
        log.info("Entry already exists for today (id=%s, %.1fh) — skipping.",
                 entry["id"], entry["unit_amount"])
        return

    # ── 4. Create timesheet entry ────────────────────────────────────────────
    values = {
        "date": str(today),
        "project_id": project["id"],
        "unit_amount": cfg["hours"],
        "name": "/",
    }
    new_id = call_kw(base, sid, "account.analytic.line", "create",
                     args=[values])

    log.info("Created timesheet entry id=%s — %.1fh logged for %s on '%s'.",
             new_id, cfg["hours"], today, project["name"])


if __name__ == "__main__":
    run(load_config())
