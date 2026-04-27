---
name: timesheet
description: Auto-fill today's Odoo timesheet with 8.0 hours. Skips weekends automatically. Usage: /timesheet
---

# /timesheet

Fills today's timesheet on https://toco.tocumulus.ai/odoo/timesheets with 8.0 hours. Skips weekends automatically.

## What to do when invoked

Run the following bash command:

```bash
python finance/timesheet-autofill/scripts/autofill_timesheet.py
```

If `ODOO_EMAIL` or `ODOO_PASSWORD` are not set in the environment, prompt the user for them before running.

If playwright is not installed, run first:
```bash
pip install playwright && playwright install chromium
```

## First-time setup (one-time only)

Ask the user to set these environment variables (or store in `finance/timesheet-autofill/assets/config.json`):

| Variable        | Example value                     |
|-----------------|-----------------------------------|
| `ODOO_URL`      | `https://toco.tocumulus.ai`       |
| `ODOO_EMAIL`    | `you@company.com`                 |
| `ODOO_PASSWORD` | `your_password`                   |
| `ODOO_PROJECT`  | Name shown in the project dropdown |

## Selector troubleshooting

If the script can't find a field, run the inspector to print all field names:

```bash
ODOO_HEADLESS=false python finance/timesheet-autofill/scripts/inspect_selectors.py
```

## Script location
→ `finance/timesheet-autofill/scripts/autofill_timesheet.py`
