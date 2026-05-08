# Offshore Budgeting Agent Playbook

Offshore Budgeting is a personal finance app built around separate budgeting contexts, flexible budget periods, card-ledger tracking, planned-vs-actual money flow, and Marina, a conversational budgeting assistant. Future agents should treat this project as a lived financial system: preserve user intent, preserve historical records, and respect the domain math before changing UI or storage.

This document combines the product manifesto with the current SwiftData model and app behavior. When code and desired product policy do not fully agree, document the current behavior and flag the decision instead of silently flattening it.

## How To Work In This Repo

- Read existing code before editing. Prefer local patterns, existing services, and tests over new abstractions.
- Treat workspace boundaries as a hard data boundary. Reads, writes, queries, widgets, shortcuts, and Marina responses should be scoped to the selected or explicitly provided workspace unless an existing cross-workspace feature intentionally says otherwise. Most reads and writes must be scoped by `workspace.id`.
- Prefer preserving financial history. Never introduce destructive cleanup as a side effect of a UI convenience change. Archive, unlink, nil out optional classifications, or route to review before deleting historical expenses, incomes, or ledger entries.
- Do not collapse product concepts just because names sound similar. In particular, `VariableExpense` and `PlannedExpense` are different models with different business meaning.
- Avoid duplicate user-facing names inside one workspace. The model often allows duplicates, but Marina and Shortcuts rely on clear resolution.
- Keep Savings and Reconciliation separate. Savings is true saved money; Reconciliation/Allocation accounts track shared balances. Do not revive legacy mirrored reconciliation savings entries. If old data requires cleanup, write an explicit normalization/migration plan before changing behavior.
- Use model-aware deletion helpers where they exist, especially `PlannedExpenseDeletionService`, `VariableExpenseDeletionService`, `BudgetDeletionService`, `SavingsAccountService`, and allocation ledger helpers.
- For SwiftData relationship changes, verify the app schema in `OffshoreBudgeting/OffshoreBudgetingApp.swift` and test schemas. The live app schema currently includes 19 models.

## Agent Workflow

Before making changes:

1. Inspect the files directly related to the request.
2. Search for existing types, helpers, services, and tests before adding new ones.
3. Summarize the current behavior and the intended change.
4. Identify the smallest safe file set.
5. Call out assumptions before implementation.
6. Prefer one focused change over broad refactors.
7. Preserve existing behavior unless the task explicitly asks to change it.

After making changes, report:

- Files changed
- Behavior changed
- Tests run
- Tests not run and why
- Risks or follow-up work

## Complex Tasks and Multi-Agent Work

For broad, risky, or multi-domain tasks, prefer phased work over one large implementation pass.

Use separate agents/workers when the task benefits from independent investigation, especially for:

- SwiftData model or relationship changes
- CloudKit compatibility risks
- Marina / NLQ routing or query-shape changes
- financial aggregation math
- savings, reconciliation, or allocation behavior
- WidgetKit, AppIntents, or Shortcut changes
- cross-platform UI behavior
- regression diagnosis
- large test-suite expansion

Each agent should have a narrow role, such as:

- Architecture Agent: inspect current files and summarize existing patterns.
- Domain Agent: verify business rules and financial math.
- Risk Agent: identify schema, CloudKit, platform, or data-loss risks.
- Test Agent: identify existing tests and missing coverage.
- Implementation Agent: make the smallest safe change.
- Review Agent: compare the final diff against the requested scope.

Do not use multi-agent work for small localized fixes.

Before implementation, summarize the findings, the recommended phase plan, and the expected files to change. Each phase should be independently reviewable.

## Build and Test Commands

Use the project’s existing schemes. Prefer running focused tests before full suites.

Common verification areas:

- Main app build
- Unit tests
- Widget extension build
- AppIntents / Shortcuts compile
- SwiftData in-memory tests

If tests cannot be run in the current environment, say so clearly and explain what should be run locally.

## Command Output

Protect context usage. **Any command with unknown or potentially large output must be byte-capped.**

Default pattern:

```bash
COMMAND 2>&1 | head -c 4000
```

## SwiftData Model Map

The confirmed model schema is:

`Workspace`, `Budget`, `BudgetCategoryLimit`, `Card`, `BudgetCardLink`, `BudgetPresetLink`, `Category`, `Preset`, `PlannedExpense`, `VariableExpense`, `AllocationAccount`, `ExpenseAllocation`, `AllocationSettlement`, `SavingsAccount`, `SavingsLedgerEntry`, `ImportMerchantRule`, `AssistantAliasRule`, `IncomeSeries`, `Income`.

Grouped by domain:

- Workspace ownership: `Workspace` owns nearly all app data and cascades most children.
- Budget participation: `Budget`, `BudgetCardLink`, `BudgetPresetLink`, `BudgetCategoryLimit`.
- Card and spending ledger: `Card`, `VariableExpense`, `PlannedExpense`.
- Categories and presets: `Category`, `Preset`.
- Reconciliation: `AllocationAccount`, `ExpenseAllocation`, `AllocationSettlement`.
- Savings: `SavingsAccount`, `SavingsLedgerEntry`.
- Income: `Income`, `IncomeSeries`.
- Import and assistant memory: `ImportMerchantRule`, `AssistantAliasRule`.

## Workspace

A workspace owns a complete budgeting context. Personal and Work can live in the same app without sharing cards, budgets, categories, income, expenses, savings, import rules, or Marina context.

Rules:

- A workspace needs a name and hex color in product flows.
- Most screens, shortcuts, widgets, and Marina queries must filter by workspace.
- The app expects at least one workspace after onboarding.
- Deleting a workspace is intentionally broad because SwiftData cascades its owned graph. Guard against deleting the final workspace and make destructive impact obvious.
- Workspace names should be treated as user-facing identifiers; avoid duplicates even when the model permits them.

## Budgets

A budget is an inclusive date range with a name. It groups income, planned expenses, variable expenses, category limits, linked cards, linked presets, and savings outcomes for a period that matches the user's budgeting brain. Preset periods such as daily, weekly, monthly, quarterly, and yearly are conveniences, not the limit of what a budget can represent.

Rules:

- Budget date ranges are inclusive.
- Creation/edit flows require non-empty name and `startDate <= endDate`.
- Cards enter a budget through `BudgetCardLink`.
- Presets enter a budget through `BudgetPresetLink`.
- Category min/max goals enter a budget through `BudgetCategoryLimit`.
- A budget does not directly own expenses. Generated planned expenses are associated by `sourceBudgetID`, not a SwiftData relationship.
- Budget planned expense lookup must use `sourceBudgetID`, linked card IDs, and date range.
- Budget deletion has multiple product meanings: delete only the budget, delete generated planned expenses, or review recorded generated expenses. Prefer preserving history and routing recorded items to review.

## Cards

A card is the spending account/card ledger used by expenses, card detail, budget scoping, widgets, shortcuts, and Marina queries. Expenses should have a card in normal product flows.

Rules:

- A card needs a non-empty name, theme, and effect in product flows.
- UI and Marina currently default new cards to Ruby/Plastic style, while the model has fallback storage defaults.
- Duplicate normalized card names are risky because Wallet-name shortcut resolution can become ambiguous.
- Deleting a card currently deletes linked planned expenses, variable expenses, incomes, and budget links in several app paths. Treat this as destructive financial history and prefer archive/unassign/review patterns for future work.

## Expenses

The manifesto's "Expense" concept maps to two concrete models. Agents must keep them distinct.

### VariableExpense

`VariableExpense` is actual card-ledger activity: user-entered transactions, card imports, shortcut-created expenses, credits/refunds, and adjustments.

Rules:

- Product creation requires non-empty description/notes, amount greater than zero, date, workspace, and card.
- Category is optional; nil category displays as virtual "Uncategorized."
- `kind` changes math:
  - Debit is spending.
  - Credit is a signed reduction.
  - Adjustment is ledger activity with zero budget impact in savings math.
- Use the right amount helper for the question:
  - `spendingAmount()` counts debit spending.
  - `ledgerSignedAmount()` reflects debit/credit/adjustment ledger signs.
  - `SavingsMathService.variableBudgetImpactAmount` accounts for allocation and savings offsets.
- Future variable expenses can be hidden from lists or excluded from calculations using user settings.
- Deleting a variable expense should use `VariableExpenseDeletionService` so linked allocation, settlement, and savings ledger entries are cleaned up.

### PlannedExpense

`PlannedExpense` is an expected dated cost, usually materialized from a preset attached to a budget. It has a planned amount and optional actual amount.

Rules:

- Product creation/editing expects title, planned amount greater than zero, date, workspace, and usually a card.
- `actualAmount == 0` currently means "not recorded yet"; effective amount falls back to planned amount.
- Effective amount uses actual amount only when `actualAmount > 0`, otherwise planned amount.
- Generated rows must carry `sourcePresetID` and `sourceBudgetID`.
- Generated planned expenses are deduped by budget ID, preset ID, and date.
- Future planned expenses can be hidden from lists or excluded from calculations independently from variable expenses.
- Deleting a planned expense should use `PlannedExpenseDeletionService` so linked allocation, settlement, and savings ledger entries are cleaned up.

## Categories

Categories organize spending and power category analytics, budget limits, imports, widgets, and Marina queries.

Rules:

- A category needs non-empty name and hex color in product flows.
- Category is optional on expenses and presets. "Uncategorized" is currently a virtual nil category, not a guaranteed stored category.
- Category names should be unique enough within a workspace for Marina and import matching.
- Budget category limits are period-scoped; there is no global category budget.
- Deleting a category should preserve historical expenses by clearing category references and deleting/repairing dependent limit rows. Current settings and Marina paths differ; flag this before changing behavior.

## Presets

A preset is a recurring planned-expense template. It materializes into `PlannedExpense` rows when attached to a budget.

Rules:

- A preset needs title, planned amount, recurrence schedule, default card, and optional default category in product flows.
- Archive hides a preset from normal management/selection without deleting already-created planned expenses.
- Materialization is budget-window scoped and should be idempotent.
- Generated planned expenses copy preset title, planned amount, default category, and default card only when the card is linked to the budget.
- Unlinking a preset from a budget deletes generated rows for that budget/preset in current flows.
- Preset deletion and edit-sync behavior differ across UI and Marina paths. Document and preserve current behavior unless implementing a deliberate product decision.

## Income

Income represents money expected or received. `isPlanned` is the semantic split: planned income is expected, actual income is received.

Rules:

- Product creation requires source, amount greater than zero, date, planned/actual state, and workspace.
- Dates are generally normalized to start of day for manual, shortcut, Marina, and recurrence-generated entries.
- Actual income drives received-income analytics.
- Planned income drives forecasts, safe-spend, reminders, and projected savings.
- `IncomeSeries` stores bounded recurrence rules and materializes concrete `Income` rows. Downstream features generally consume `Income`, not recurrence rules.
- Series edits must preserve exceptions when regenerating child rows.
- Deleting card-linked income currently appears destructive through card deletion. Treat this as a history-preservation decision point.

## Savings

Savings is the true-savings ledger. The app treats the first `SavingsAccount` in a workspace as the primary account and uses `SavingsLedgerEntry` rows as the source of truth for account total.

Rules:

- `SavingsAccount.total` is derived from ledger entries and must be recalculated after mutations.
- Ledger kinds are `periodClose`, `manualAdjustment`, `expenseOffset`, and `reconciliationSettlement`.
- Manual adjustments affect actual savings math.
- Period-close and expense-offset entries are system-managed.
- Expense offsets are negative ledger entries linked to a planned or variable expense.
- Current tests allow savings offsets to exceed available account total; if product policy changes, update service behavior and tests together.
- Reconciliation settlement savings entries are legacy/mirrored data and should be normalized away, not revived.

## Reconciliation / Allocation Accounts

Reconciliation accounts, modeled as `AllocationAccount`, track shared balances outside normal card and savings balances. They answer "what portion belongs to someone/something else?" rather than "how much did I save?"

Rules:

- A reconciliation account needs non-empty name and color in product flows.
- Accounts with history should generally be archived rather than deleted.
- `ExpenseAllocation` is a split charge against an allocation account. It should link to exactly one `VariableExpense` or one `PlannedExpense`, even though the model does not enforce XOR.
- Split amounts are capped to the linked expense/planned amount.
- Current allocations generally preserve gross expense amount while reducing owned/budget impact by the allocated share.
- `AllocationSettlement` is a signed ledger settlement. Standalone settlements do not mirror into savings.
- Split and offset modes are mutually exclusive in expense forms.

## Imports

Imports turn CSV/PDF/image/clipboard data into expenses or income, with learning rules for merchant cleanup and category suggestions.

Rules:

- `ImportMerchantRule` maps normalized merchant keys to optional preferred display names and categories.
- Explicit category selection wins over learned merchant-rule fallback.
- Merchant keys should be produced through the app's normal merchant normalizer.
- Learned rules are workspace-scoped and text/category based; category deletion and renames can stale them.
- There is currently no main settings UI for learned import rules. Treat edits/deletes as a product decision, not a casual cleanup.

## Marina

Marina is the conversational layer over the user's current workspace. It answers budget questions, handles some CRUD, and should ask clarifying questions when names or target types are ambiguous.

Rules:

- Marina must be workspace-scoped.
- Marina should distinguish cards, merchants, categories, budgets, presets, income sources, savings accounts, and reconciliation accounts.
- If a prompt can mean both a card and merchant/expense text, ask for clarification.
- Marina supports CRUD for core user-facing entities, but not every supporting ledger entity.
- `AssistantAliasRule` stores workspace-scoped text aliases for assistant resolution. It points to text, not stable entity IDs, so renames/deletes can make aliases stale.
- Alias uniqueness should be normalized/case-insensitive in product thinking, even though current upsert is more literal.

## Home, Widgets, And Shortcuts

Home is a wide workspace summary over a selected date range. Widgets and Shortcuts consume curated snapshots or selected-workspace data.

Rules:

- Home and widgets must use the selected workspace.
- Widget snapshots are derived data; rebuild through existing snapshot builders rather than inventing parallel calculations.
- Safe-spend, forecast savings, card snapshots, spend trends, income widgets, and next planned expense widgets each have existing builders/tests.
- Shortcuts resolve the selected workspace, then resolve entities within that workspace.
- Add Expense shortcut resolves explicit Offshore card ID before Wallet card name. Ambiguous normalized card names should fail rather than guess.
- Add Income shortcut creates one-off income only.

## Calculation Rules Agents Must Respect

- Budget ranges are inclusive.
- Planned expenses for a budget are scoped by `sourceBudgetID`, linked card IDs, and date range.
- `PlannedExpense.actualAmount == 0` currently means use planned amount.
- Variable expense totals depend on intent: spending, ledger, and budget impact are not interchangeable.
- Split allocations reduce owned/budget impact while preserving gross ledger history.
- Savings offsets reduce budget impact through negative savings ledger entries.
- Savings totals are derived from `SavingsLedgerEntry` rows.
- Reconciliation balances are positive allocations plus signed settlements.
- "Uncategorized" is virtual nil category unless a real category is explicitly created.
- Future planned and future variable expenses have separate visibility/calculation settings.

## Known Decision Flags

These are current behavior mismatches or product choices future agents should not resolve accidentally:

- Preset deletion and generated planned-expense cleanup differ across paths.
- Preset edits sync generated planned expenses in some Marina flows but not every UI flow.
- Category deletion cleanup differs between Marina and settings/onboarding.
- Card deletion currently destroys linked expenses/incomes in several paths.
- Budgets can overlap; the app tolerates this, but overlapping active budget semantics should be intentional.
- Budgets with zero linked cards are possible but disable some budget-scoped expense behavior.
- Savings offsets may exceed available savings total today.
- `AssistantAliasRule` and `ImportMerchantRule` are text-based and can stale after renames/deletes.
- There is no guaranteed uniqueness constraint for workspace, card, category, budget, preset, or alias names.

## Useful Verification Targets

When changing business logic, look for or add focused tests near:

- `OffshoreBudgetingTests/SwiftDataCRUDTests.swift`
- `OffshoreBudgetingTests/SwiftDataDeletionRulesTests.swift`
- `OffshoreBudgetingTests/BudgetPlannedExpenseStoreTests.swift`
- `OffshoreBudgetingTests/BudgetDeletionServiceTests.swift`
- `OffshoreBudgetingTests/SavingsAccountServiceTests.swift`
- `OffshoreBudgetingTests/AllocationLedgerServiceTests.swift`
- `OffshoreBudgetingTests/AddExpenseShortcutExecutorTests.swift`
- `OffshoreBudgetingTests/OffshoreIntentDataStoreResolutionTests.swift`
- `OffshoreBudgetingTests/MarinaCrudParityTests.swift`
- `OffshoreBudgetingTests/HomeQueryEngineTests.swift`

For model/schema work, verify `OffshoreBudgeting/Models.swift`, `OffshoreBudgeting/OffshoreBudgetingApp.swift`, and any in-memory test schemas together.
