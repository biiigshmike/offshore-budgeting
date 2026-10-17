# Offshore Budgeting

Offshore Budgeting is a SwiftUI personal finance app for budgeting across separate workspaces. It tracks budgets, cards, planned expenses, variable expenses, income, savings, reconciliation/allocation accounts, widgets, shortcuts, imports, and Marina, the conversational budgeting assistant.

## Start Here

- `AGENTS.md` is the project playbook. Read it before changing financial logic, SwiftData relationships, deletion behavior, Marina routing, widgets, or shortcuts.
- `CODEMAP.md` is the fast navigation map for GitHub, Atlas, and code assistants.
- `OffshoreBudgeting/Models.swift` defines the main SwiftData schema and shared domain helpers.
- `OffshoreBudgeting/OffshoreBudgetingApp.swift` wires the app schema, model container, app commands, and root app state.
- `OffshoreBudgetingTests/` contains the focused unit coverage for domain math, SwiftData behavior, Marina, widgets, shortcuts, imports, and app services.

## Project Layout

- `OffshoreBudgeting/` contains the main SwiftUI app, SwiftData models, services, views, AppIntents, import parsers, localization, and asset catalogs.
- `OffshoreBudgeting/CoreViews/Home/Marina/` contains Marina's UI surface, conversational state, semantic parsing, query planning, query execution, and answer presentation.
- `OffshoreBudgetingWidgets/` contains WidgetKit timelines, snapshot stores, AppIntent-backed widget configuration, control widgets, and Live Activity support.
- `OffshoreBudgetingTests/` contains in-memory SwiftData tests and focused feature tests. Prefer adding narrow tests near existing coverage instead of broad snapshot-style tests.
- `Docs/` contains generated or curated supporting project data.
- `Scripts/` contains local maintenance scripts.
- `Templates/` contains reference templates and is usually unrelated to app behavior.

## Analysis Notes

The repository intentionally includes a large app asset catalog, including help screenshots under `OffshoreBudgeting/Assets.xcassets`. These image assets are important to the app but are usually irrelevant when analyzing Swift code, domain behavior, tests, or Marina logic.

For most code work, inspect Swift files and tests first. Avoid spending analysis budget on PNG/PDF assets, `.xcuserdata`, `.DS_Store`, local build products, or generated screenshots unless the task explicitly concerns visual help content or asset packaging.

## Common Verification

Use the existing Xcode scheme and focused tests. For business logic changes, prefer the targeted tests named in `AGENTS.md` before running broader suites.
