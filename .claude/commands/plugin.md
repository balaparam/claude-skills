---
description: Manage Claude Skills marketplace plugins. Add marketplaces and install skill packages. Usage: /plugin marketplace add <source> | /plugin install <plugin>@<marketplace>
---

Parse `$ARGUMENTS` and execute the appropriate plugin operation below.

---

## Operation: `marketplace add <github-handle/repo>`

Example: `/plugin marketplace add alirezarezvani/claude-skills`

1. Extract the GitHub source from the argument (the part after "marketplace add").
2. Fetch the marketplace manifest from:
   `https://raw.githubusercontent.com/<github-handle/repo>/main/.claude-plugin/marketplace.json`
3. Validate the JSON structure — confirm it has `name` and `plugins` array fields.
4. Display a formatted summary table of all available plugins:
   | Plugin | Category | Description |
   |--------|----------|-------------|
   (populate from the `plugins` array)
5. Persist the marketplace registration to `.claude/settings.json` (create the file if it doesn't exist):
   ```json
   {
     "plugins": {
       "marketplaces": {
         "<marketplace-name>": "<github-handle/repo>"
       }
     }
   }
   ```
6. Confirm: "Marketplace `<name>` added. Run `/plugin install <plugin>@<marketplace-name>` to install skills."

---

## Operation: `install <plugin-name>@<marketplace-name>`

Example: `/plugin install playwright-pro@claude-code-skills`

1. Parse `<plugin-name>` and `<marketplace-name>` from the argument (split on `@`).
2. Resolve the marketplace GitHub source:
   - Check `.claude/settings.json` → `plugins.marketplaces.<marketplace-name>`
   - If not found and marketplace name is `claude-code-skills`, default to `alirezarezvani/claude-skills`
   - Otherwise error: "Marketplace `<marketplace-name>` not registered. Run `/plugin marketplace add <source>` first."
3. Fetch the marketplace manifest from:
   `https://raw.githubusercontent.com/<source>/main/.claude-plugin/marketplace.json`
4. Find the plugin entry where `name` matches `<plugin-name>`. If not found, list available plugin names and stop.
5. Resolve the plugin's source path from the `source` field in the manifest entry.
6. Fetch and display the plugin's `SKILL.md` (or equivalent root README) from:
   `https://raw.githubusercontent.com/<source>/main/<source-path>/SKILL.md`
   to confirm it is a valid skill package.
7. Copy the plugin into `.claude-skills/<plugin-name>/` in the current project by fetching its key files (SKILL.md, scripts/, references/, assets/). Use the GitHub API tree endpoint to enumerate files:
   `https://api.github.com/repos/<owner>/<repo>/git/trees/main?recursive=1`
   Filter paths that start with `<source-path>/`.
8. Update `.claude/settings.json` to record the installation:
   ```json
   {
     "plugins": {
       "installed": {
         "<plugin-name>": {
           "marketplace": "<marketplace-name>",
           "source": "<github-handle/repo>",
           "path": ".claude-skills/<plugin-name>",
           "version": "<version-from-manifest>"
         }
       }
     }
   }
   ```
9. Summarize the installed skill's capabilities (from its SKILL.md) in 3–5 bullet points.
10. Confirm: "Installed `<plugin-name>` v<version>. Skill capabilities are now active in this project."

---

## Operation: `list` (optional)

Example: `/plugin list`

1. Read `.claude/settings.json` → `plugins.installed`.
2. Display a table of installed plugins with name, version, and marketplace source.
3. If nothing installed: "No plugins installed yet. Run `/plugin marketplace add <source>` to get started."
