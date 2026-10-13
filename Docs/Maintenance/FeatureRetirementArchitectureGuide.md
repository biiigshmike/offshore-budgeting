# Maintaining Offshore Budgeting after feature retirement

The app already has useful separation: SwiftData classes represent stored records, financial services own important rules, and some workflows have view models. The strongest next improvement is reducing the responsibilities of large screens. More classes or inheritance alone would not make the app easier to maintain.

## A Java-to-Swift mental map

| Responsibility | Swift pattern in this app |
| --- | --- |
| Persistent entity | `@Model final class`, such as `Workspace` or `VariableExpense` |
| Screen rendering | A `struct` conforming to `View` |
| Screen workflow and observable state | A focused controller/view model, preferably `@MainActor @Observable` for new code |
| Financial rule or operation | A service such as `SavingsMathService` or `BudgetDeletionService` |
| Small immutable input/output | A `struct` |

SwiftUI views are value types that describe what to display. Their being structs is normal; converting them to classes is not the route to OOP. `@State` gives the screen state that persists across view updates, and `@Query` keeps SwiftData results current. Classes are appropriate for identity, shared mutable state, and long-lived workflows. Composition and narrow protocols can provide the dependency boundaries familiar from Java without a base-class hierarchy.

## Home now has a focused ViewModel

`HomeViewModel` is a `@MainActor @Observable final class` that owns dashboard preparation and caching, three cancellable refresh/housekeeping tasks, applied date-range preferences, and pinned-item loading, editing persistence, migration, and sync handling. The view owns it with `@State`, and the Home root has an explicit workspace identity so work and state cannot follow the user into another workspace.

`HomeView` retains workspace-scoped `@Query` results and passes them into the ViewModel. It also retains rendering, sheets, draft date-picker values, global `@AppStorage` settings observation, and measured layout sizes. Applied dates are read-only ViewModel outputs; pins use `@Bindable` to keep the existing editor working while the ViewModel handles persistence. Incoming synced pins do not trigger an immediate outgoing push.

The refactor preserves current Home behavior, including resetting a custom applied range to the current default budgeting period on appearance. It does not centralize tile formulas or change financial math. Use the focused ViewModel tests as examples for cancellation, workspace isolation, date preferences, and pin sync. Any later preference-policy or formula changes should be separate, deliberate work.

## Preserve the useful domain boundaries

`SavingsMathService` already distinguishes gross, owned, and budget-impact amounts, including credits, adjustments, allocations, and savings offsets. `BudgetDeletionService` distinguishes deleting a budget alone from deleting its generated planned expenses and delegates expense deletion to the model-aware helper. These boundaries are valuable: UI controllers should call them rather than reproduce their rules.

`ExpenseCSVImportViewModel` demonstrates existing MVVM: it owns loading state, review rows, grouping, validation, and import actions. Its current `ObservableObject`/`@Published` implementation is established code; an Observation migration should be its own justified change. If import work becomes hard to change, extract one cohesive operation at a time, such as document parsing or matching, while preserving the review workflow. Do not add generic repositories, base view models, or one wrapper per model as a blanket cleanup.

For small forms and lists, local `@State`, scoped `@Query`, and calls to domain services can remain sufficient. Add a view model when there is a substantial workflow, asynchronous lifecycle, or state transition worth testing independently.

## Rebuild the retired features incrementally

For Marina, begin with one workspace-scoped, read-only question. Keep conversation presentation and loading/error state in a small controller; put interpretation and execution behind explicit interfaces that receive the workspace ID. Use existing financial helpers. Add each write operation only after its validation, ambiguity handling, and history-preservation behavior are covered independently. Store conversation data separately from budgeting operations.

For Excursion, begin with a manually started session and explicit states. Keep session transitions in a small controller and location, notifications, and ActivityKit behind narrow adapters. Add automatic detection only after start, stop, cancellation, and app-relaunch behavior work reliably. Ordinary quick-add must remain usable without the feature.

Retained Marina model definitions and Excursion Activity attributes are upgrade-compatibility code, not an active feature architecture. **Before a rebuilt feature saves records or starts sessions, disable or replace its retirement cleanup:** otherwise that cleanup may delete new conversations/aliases or end new sessions. Review the retained storage and CloudKit compatibility before changing model shape, and verify upgrades as well as fresh installs.

Use the completed Home refactor as a reference for whichever remaining workflow is hardest to change. Make each extraction independently buildable and reviewable, with no financial behavior change bundled into it.
