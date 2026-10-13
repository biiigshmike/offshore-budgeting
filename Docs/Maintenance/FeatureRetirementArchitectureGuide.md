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

## Improve Home first, in a separate change

`HomeView` currently combines layout, date-range preferences, pinned-item management, snapshot construction/cache access, and three cancellable tasks for refresh, housekeeping, and activation enrichment. That is a concrete maintenance concern, rather than evidence that every screen needs MVVM.

Extract the snapshot and task orchestration into a focused `@MainActor @Observable` Home controller. Give it explicit inputs for workspace identity, date range, future-expense policies, and activation state; keep existing snapshot and financial helpers. Cancel pending work when its inputs or owning screen change, and reject results for an obsolete workspace or activation token. Start by retaining `@Query` in the view and passing its scoped results to the controller; do not introduce a second database-observation system merely to satisfy MVVM.

Leave rendering, sheets, draft form values, and measured layout sizes in the view. Keep `@AppStorage` preferences in the view or an explicit preferences adapter; do not move the wrapper into an observable class. Test the extracted controller for rapid range/workspace changes, cancellation, and preservation of current future-expense behavior before separately considering date preferences or layout extraction.

## Preserve the useful domain boundaries

`SavingsMathService` already distinguishes gross, owned, and budget-impact amounts, including credits, adjustments, allocations, and savings offsets. `BudgetDeletionService` distinguishes deleting a budget alone from deleting its generated planned expenses and delegates expense deletion to the model-aware helper. These boundaries are valuable: UI controllers should call them rather than reproduce their rules.

`ExpenseCSVImportViewModel` demonstrates existing MVVM: it owns loading state, review rows, grouping, validation, and import actions. Its current `ObservableObject`/`@Published` implementation is established code; an Observation migration should be its own justified change. If import work becomes hard to change, extract one cohesive operation at a time, such as document parsing or matching, while preserving the review workflow. Do not add generic repositories, base view models, or one wrapper per model as a blanket cleanup.

For small forms and lists, local `@State`, scoped `@Query`, and calls to domain services can remain sufficient. Add a view model when there is a substantial workflow, asynchronous lifecycle, or state transition worth testing independently.

## Rebuild the retired features incrementally

For Marina, begin with one workspace-scoped, read-only question. Keep conversation presentation and loading/error state in a small controller; put interpretation and execution behind explicit interfaces that receive the workspace ID. Use existing financial helpers. Add each write operation only after its validation, ambiguity handling, and history-preservation behavior are covered independently. Store conversation data separately from budgeting operations.

For Excursion, begin with a manually started session and explicit states. Keep session transitions in a small controller and location, notifications, and ActivityKit behind narrow adapters. Add automatic detection only after start, stop, cancellation, and app-relaunch behavior work reliably. Ordinary quick-add must remain usable without the feature.

Retained Marina model definitions and Excursion Activity attributes are upgrade-compatibility code, not an active feature architecture. **Before a rebuilt feature saves records or starts sessions, disable or replace its retirement cleanup:** otherwise that cleanup may delete new conversations/aliases or end new sessions. Review the retained storage and CloudKit compatibility before changing model shape, and verify upgrades as well as fresh installs.

Prioritize Home orchestration first, then whichever remaining workflow is hardest to change. Make each extraction independently buildable and reviewable, with no financial behavior change bundled into it.
