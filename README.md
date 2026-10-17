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
- `OffshoreBudgeting/Marina/` contains Marina's UI, conversation history, Foundation Models tools, workspace-bound queries, and answer presentation.
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


## Marina assistant

Marina opens from Home on iOS 26+ and Mac Catalyst using Apple's on-device Foundation Models. Apple Intelligence must be available; saved conversations remain readable otherwise. The app's existing iOS 18.6 deployment target is preserved.

The model interprets natural language through three typed, read-only tools: resolve workspace entities, find records, and calculate statistics. Swift validates workspace ownership, resolves calendar periods, and performs financial arithmetic. Debit spending, signed ledger activity, owned amounts, budget impact, true savings, reconciliation balances, and period surplus remain distinct. Exact result cards and native charts come from tool outputs, while explanatory prose is generated from a separate compact facts-only context. Typed amount scope distinguishes unrestricted searches from ranges and approximate targets; Swift applies the ±10% approximation.

History uses versioned Codable payloads in the existing `MarinaChatSession` model and follows the app's iCloud setting. History saves use a separate context so they cannot save unrelated financial edits. The obsolete Marina retirement purge has been removed; do not reintroduce cleanup that deletes active conversations. Alias models remain dormant for compatibility. Older installed app versions still contain the purge, so update all syncing devices before relying on saved Marina history.

Requests have a 60-second deadline and an eight-tool-call limit. Cancellation and workspace changes invalidate stale completions. Context overflow receives one shorter retry without duplicating the question. Unsupported history payloads are preserved. Records opened from saved answers are resolved against current workspace data.

Run `MarinaQueryServiceTests`, `MarinaConversationTests`, and `MarinaSmokeTests`, plus the existing savings/allocation/budget/trend regression tests when shared math changes. Build iOS and Mac Catalyst. Evaluate real inference separately from deterministic tool tests: paraphrases, week/month searches, follow-ups, all financial domains, advice requests, long chats, and duplicate names. On-device model interpretation and refusals vary; guided generation constrains structure, not factual truth. Validate Apple Intelligence on iPhone/iPad, VoiceOver/Dynamic Type/chart behavior, and actual iCloud sync before release.

Current verification: iOS simulator and Mac Catalyst builds pass, including shared widget/AppIntents compilation. There are 38 passing Marina query/conversation tests, one passing Home/history UI smoke test, and 61 passing existing domain regression cases. Synthetic on-device evaluation on this Mac verified the supplied remembered-$100 week request includes all four records across two cards, including a $150 transaction. Earlier live runs exposed over-filtering; the explicit amount scope corrected that case. A focused live follow-up changed the weekly list into a correctly calculated $285 recorded-spending total after previous context was reduced to filters. Compound account names and month-versus-named-budget interpretation still need broader device evaluation. Actual iCloud sync, physical iPhone/iPad inference, version 26/27 device coverage, and full accessibility/layout validation remain release checks, not claims established by simulator tests.
