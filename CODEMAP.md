# Offshore Budgeting Code Map

This file is a fast orientation guide for GitHub, Atlas, and code assistants. For product rules and safety constraints, read `AGENTS.md`.

## Core App And Schema

- `OffshoreBudgeting/Models.swift` defines the SwiftData models: workspaces, budgets, cards, planned and variable expenses, categories, presets, income, savings, reconciliation/allocation accounts, imports, and assistant aliases.
- `OffshoreBudgeting/OffshoreBudgetingApp.swift` defines the live app model schema and app bootstrap.
- `OffshoreBudgeting/CoreViews/` contains the primary SwiftUI feature surfaces.
- `OffshoreBudgeting/Localizable.xcstrings` contains app localization strings and is large; inspect only when changing user-facing copy.

## Financial Services And Domain Logic

Look for existing services before adding new behavior. Important service areas include deletion helpers, savings math, allocation/reconciliation ledgers, budget planned expense materialization, imports, workspace handling, and widget snapshot builders.

Useful search terms:

- `PlannedExpenseDeletionService`
- `VariableExpenseDeletionService`
- `BudgetDeletionService`
- `SavingsAccountService`
- `SavingsMathService`
- `AllocationLedgerService`
- `BudgetPlannedExpenseStore`
- `WorkspaceTransferService`

## Marina And Natural Language Queries

- `OffshoreBudgeting/CoreViews/Home/Marina/Surface/` contains Marina UI, conversation persistence, inline create forms, and prompt submission behavior.
- `OffshoreBudgeting/CoreViews/Home/Marina/Brain/` contains interpreters, semantic request types, candidate resolution, validation, query planning, query execution, answer seeds, and answer presentation.
- `OffshoreBudgeting/CoreViews/Home/HomeQueryModels.swift` defines home query models, lookup object types, clarification choices, and query-facing data shapes.

Useful search terms:

- `MarinaBrain`
- `MarinaHybridInterpreter`
- `MarinaSemanticTypes`
- `MarinaSemanticRequestValidator`
- `MarinaSemanticCandidateResolver`
- `MarinaQueryPlanner`
- `MarinaQueryExecutor`
- `MarinaAnswerPresenter`
- `MarinaCreateService`

## Widgets, Shortcuts, And AppIntents

- `OffshoreBudgetingWidgets/` contains WidgetKit providers, timeline snapshots, control widgets, and Live Activity support.
- Widget domains include cards, spend trends, income, safe spend, forecast savings, next planned expense, and excursion/shopping mode.
- Shortcut and AppIntent behavior lives across the main app and widget extension. Resolve workspace and card/category/budget names carefully; ambiguity should fail or clarify rather than guess.

Useful search terms:

- `AddExpenseShortcutExecutor`
- `OffshoreIntentDataStoreResolution`
- `WidgetTimelineSnapshotStorage`
- `CardWidgetSnapshotStore`
- `SpendTrendsWidgetSnapshotStore`
- `IncomeWidgetSnapshotStore`
- `NextPlannedExpenseWidgetSnapshotStore`

## Tests To Prefer

For focused changes, start near these tests:

- `OffshoreBudgetingTests/SwiftDataCRUDTests.swift`
- `OffshoreBudgetingTests/SwiftDataDeletionRulesTests.swift`
- `OffshoreBudgetingTests/BudgetPlannedExpenseStoreTests.swift`
- `OffshoreBudgetingTests/BudgetDeletionServiceTests.swift`
- `OffshoreBudgetingTests/SavingsAccountServiceTests.swift`
- `OffshoreBudgetingTests/AllocationLedgerServiceTests.swift`
- `OffshoreBudgetingTests/AddExpenseShortcutExecutorTests.swift`
- `OffshoreBudgetingTests/OffshoreIntentDataStoreResolutionTests.swift`
- `OffshoreBudgetingTests/HomeQueryEngineTests.swift`
- `OffshoreBudgetingTests/MarinaCreateServiceTests.swift`
- `OffshoreBudgetingTests/MarinaSemanticPromptSuiteTests.swift`
- `OffshoreBudgetingTests/MarinaFoundationModelPromptEvaluationTests.swift`

## Usually Ignore During Code Analysis

- `OffshoreBudgeting/Assets.xcassets/**` image files, unless changing app icons, help screenshots, or asset packaging.
- `OffshoreBudgetingWidgets/Assets.xcassets/**` image files, unless changing widget assets.
- `Templates/`, unless the task mentions templates.
- `Docs/MarinaEntityParity/inventory-index.json`, unless the task concerns Marina entity parity inventory.
- Local build folders such as `.build/` and `.deriveddata/`.
