# Offshore Budgeting

Offshore Budgeting is a SwiftUI personal finance app for budgeting across separate workspaces. It tracks budgets, cards, planned expenses, variable expenses, income, savings, reconciliation/allocation accounts, widgets, shortcuts, and imports.

## Start Here

- `AGENTS.md` is the project playbook. Read it before changing financial logic, SwiftData relationships, deletion behavior, widgets, or shortcuts.
- `CODEMAP.md` is the fast navigation map for GitHub, Atlas, and code assistants.
- `OffshoreBudgeting/Models.swift` defines the main SwiftData schema and shared domain helpers.
- `OffshoreBudgeting/OffshoreBudgetingApp.swift` wires the app schema, model container, app commands, and root app state.
- `OffshoreBudgetingTests/` contains the focused unit coverage for domain math, SwiftData behavior, widgets, shortcuts, imports, and app services.

## Project Layout

- `OffshoreBudgeting/` contains the main SwiftUI app, SwiftData models, services, views, AppIntents, import parsers, localization, and asset catalogs.
- `OffshoreBudgetingWidgets/` contains WidgetKit timelines, snapshot stores, AppIntent-backed widget configuration, control widgets, and Live Activity support.
- `OffshoreBudgetingTests/` contains in-memory SwiftData tests and focused feature tests. Prefer adding narrow tests near existing coverage instead of broad snapshot-style tests.
- `Docs/` contains generated or curated supporting project data.
- `Scripts/` contains local maintenance scripts.
- `Templates/` contains reference templates and is usually unrelated to app behavior.

## Analysis Notes

The repository intentionally includes a large app asset catalog, including help screenshots under `OffshoreBudgeting/Assets.xcassets`. These image assets are important to the app but are usually irrelevant when analyzing Swift code, domain behavior, tests.

For most code work, inspect Swift files and tests first. Avoid spending analysis budget on PNG/PDF assets, `.xcuserdata`, `.DS_Store`, local build products, or generated screenshots unless the task explicitly concerns visual help content or asset packaging.

## Common Verification

Use the existing Xcode scheme and focused tests. For business logic changes, prefer the targeted tests named in `AGENTS.md` before running broader suites.

## Retired Assistant

Marina chat has been removed. Existing financial records and app features remain independent of chat. `AssistantAliasRule` and `MarinaChatSession` remain only as inactive SwiftData compatibility models so existing Local and iCloud stores can open safely; do not restore assistant behavior or erase stores to remove them. Legacy workspace archive alias fields are accepted for compatibility and are not imported into new workspaces.
