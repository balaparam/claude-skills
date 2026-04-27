---
name: timesheet-autofill
description: Automatically fills 8.0 hours on an Odoo timesheet every weekday using Playwright browser automation. Skips weekends. Works with tocumulus.ai or any Odoo instance.
---

# Timesheet Auto-Fill Skill

Automates daily timesheet entry on Odoo (tested with `toco.tocumulus.ai`). Logs in, opens a new timesheet line, selects the project dropdown, enters **8.0 hours**, and saves — every weekday.

## Quick Start

### 1. Install dependencies

```bash
pip install playwright
playwright install chromium
```

### 2. Configure credentials

**Option A — environment variables (recommended, no secrets in files)**

```bash
export ODOO_URL="https://toco.tocumulus.ai"
export ODOO_EMAIL="you@company.com"
export ODOO_PASSWORD="your_password"
export ODOO_PROJECT="Internal"   # optional: name of the project to select
```

**Option B — config file**

```bash
cp assets/config.example.json assets/config.json
# edit config.json with your credentials
```

> `config.json` is git-ignored. Never commit credentials.

### 3. Run once (test manually)

```bash
# Watch the browser fill the form:
ODOO_HEADLESS=false python scripts/autofill_timesheet.py

# Run silently (headless):
python scripts/autofill_timesheet.py
```

### 4. Schedule daily (weekdays only)

The script already skips weekends. Schedule it to run every weekday morning.

**macOS / Linux — cron (9:00 AM Mon–Fri)**

```bash
crontab -e
# Add this line:
0 9 * * 1-5 ODOO_URL=https://toco.tocumulus.ai ODOO_EMAIL=you@company.com ODOO_PASSWORD=secret /usr/bin/python3 /path/to/scripts/autofill_timesheet.py >> /tmp/timesheet.log 2>&1
```

**macOS — launchd plist** (survives reboots, more reliable than cron)

Create `~/Library/LaunchAgents/com.timesheet.autofill.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.timesheet.autofill</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>/FULL/PATH/TO/scripts/autofill_timesheet.py</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>ODOO_URL</key>       <string>https://toco.tocumulus.ai</string>
        <key>ODOO_EMAIL</key>     <string>you@company.com</string>
        <key>ODOO_PASSWORD</key>  <string>your_password</string>
        <key>ODOO_PROJECT</key>   <string>Internal</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>   <integer>9</integer>
        <key>Minute</key> <integer>0</integer>
        <key>Weekday</key> <integer>1</integer>
    </dict>
    <key>StandardOutPath</key>  <string>/tmp/timesheet.log</string>
    <key>StandardErrorPath</key><string>/tmp/timesheet.log</string>
</dict>
</plist>
```

Load it:
```bash
launchctl load ~/Library/LaunchAgents/com.timesheet.autofill.plist
```

**Windows — Task Scheduler**

```
Action:  python C:\path\to\scripts\autofill_timesheet.py
Trigger: Daily, 9:00 AM, repeat Mon–Fri
Environment: Set ODOO_* variables in System Properties > Environment Variables
```

---

## Troubleshooting Selectors

If the script cannot find a field (Odoo layouts vary by version and customization), run the inspector first:

```bash
ODOO_HEADLESS=false python scripts/inspect_selectors.py
```

This opens a visible browser, logs in, clicks New, and prints every input field's `name`, `id`, and `placeholder`. Use those values to update the locator strings inside `autofill_timesheet.py`.

Common Odoo field names:

| Field   | Typical `name` attribute |
|---------|--------------------------|
| Date    | `date`                   |
| Project | `project_id`             |
| Task    | `task_id`                |
| Hours   | `unit_amount`            |

---

## Using with ChatGPT / Claude / Comet Browser

Instead of scheduling, you can trigger the script via a **Claude Code slash command** or ask your AI assistant to run it:

```
# In Claude Code terminal:
python finance/timesheet-autofill/scripts/autofill_timesheet.py
```

Or paste this into any ChatGPT / Claude chat that has terminal access:

```
Run: python /path/to/scripts/autofill_timesheet.py
(with ODOO_EMAIL and ODOO_PASSWORD set)
```

---

## Configuration Reference

| Variable / Key  | Default                        | Description                              |
|-----------------|--------------------------------|------------------------------------------|
| `ODOO_URL`      | `https://toco.tocumulus.ai`    | Base URL of your Odoo instance           |
| `ODOO_EMAIL`    | —                              | Login email (required)                   |
| `ODOO_PASSWORD` | —                              | Login password (required)                |
| `ODOO_PROJECT`  | first in dropdown              | Project name to search/select            |
| `ODOO_HOURS`    | `8.0`                          | Hours to log                             |
| `ODOO_HEADLESS` | `true`                         | Set `false` to watch the browser         |

---

## Security Notes

- Store credentials in environment variables, not in committed files.
- `assets/config.json` is git-ignored by default.
- If your org uses SSO/SAML, set `ODOO_HEADLESS=false` for the first run to complete MFA manually; the session cookie will then persist.
