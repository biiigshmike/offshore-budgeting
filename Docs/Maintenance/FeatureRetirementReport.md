# Marina and Excursion retirement handoff

## Result

Marina and Excursion UI and runtime logic are removed. Shared budgeting, savings, reconciliation, import, notification reminder, ordinary Quick Add, and remaining widget services stay in place. The existing Xcode schemes and the 20-model SwiftData schema remain unchanged. No CloudKit schema deployment or production data operation was performed.

The original two modified Marina Foundation Models files are recoverable in commit `91c55fd4`. Marina retirement is separately committed in `8912fe1f`; Excursion retirement is in `5e07b29`. Commits include summaries and descriptions; they are local, not pushed.

## Changed files and behavior

- Removed `OffshoreBudgeting/CoreViews/Home/Marina/`, the assistant-only `HomeQueryEngine.swift` and `HomeQueryModels.swift`, Marina tests, and assistant screenshots. Removed assistant presentation from Home/root, settings debug controls, debug seeding, active help topics, and obsolete localization checks.
- Added `Services/MarinaRetirementService.swift` and its tests. Launch/foreground and completed CloudKit-import hooks purge conversations and aliases in an isolated context. Failed saves roll back and subsequent invocations retry. The explicit cross-workspace purge includes orphaned assistant records. Financial models are untouched.
- Retained `AssistantAliasRule`, `MarinaAliasEntityType`, `MarinaChatSession`, their relationships, and schema registrations. Updated compatibility comments in `Models.swift`.
- Updated workspace export/import and `WorkspaceTransferServiceTests.swift`: new exports contain an empty legacy alias field; legacy archives still decode and restore financial content without restoring aliases. Alias selection was already hidden in the existing transfer UI; it remains hidden.
- Removed `OffshoreBudgeting/ShoppingMode/`, session shortcuts, widget controls, Live Activity UI, feature deep links, nearby-purchase notifications, and feature-specific Cards navigation. Removed Excursion controls from notification/privacy settings. Ordinary expense/income Quick Add and financial reminders remain.
- Added `Services/ExcursionRetirementService.swift`, `Services/LegacyExcursionActivityAttributes.swift`, and retirement tests. App initialization performs compatibility cleanup even on a background launch. Cleanup removes known defaults in standard/app-group stores, ends legacy Activities, stops legacy monitored regions/significant location updates, and cancels only feature notification identifiers. It never requests permissions or starts a session.
- Updated widget bundle/actions, project source-sharing exceptions, active app/widget localizations, help/FAQ tests, and `Scripts/localization_audit.sh`. Historical release notes remain.
- Updated `AGENTS.md` and added the architecture guide. Financial services were not refactored. Unrelated `xcshareddata/xcodecloud/` files remain untouched.

Git diffs on the recovery/removal commits provide the complete tracked-file inventory.

## Verification

- Standalone Marina phase: main app scheme build succeeded, including widget extension and remaining AppIntents.
- Combined feature removal: main app/widget simulator build succeeded; focused simulator tests passed: **93 tests in 12 suites**. A final build after restoring temporary compatibility declarations also succeeded.
- Suites: MarinaRetirementServiceTests, ExcursionRetirementServiceTests, WorkspaceTransferServiceTests, SwiftDataCRUDTests, SwiftDataDeletionRulesTests, BudgetPlannedExpenseStoreTests, BudgetDeletionServiceTests, SavingsAccountServiceTests, AllocationLedgerServiceTests, AddExpenseShortcutExecutorTests, OffshoreIntentDataStoreResolutionTests, HelpFAQEngineTests.
- Retirement tests cover repeat cleanup, later-arriving assistant records, save-failure rollback/retry, unrelated unsaved edits, scoped defaults/system-resource selection, and ordinary Quick Add preservation. Transfer tests cover legacy aliases and financial payload preservation.
- Full localization audit: all reported counters zero. Swift syntax checks, plist/project lint, and diff whitespace checks passed.
- Seeded local-only simulator launch and visual Home check passed: the dashboard renders without a Marina entry point. Onboarding, release-note, and Home-tip overlays were bypassed with launch defaults solely for this check.
- Build/test logs and the simulator test result bundle were written under `/private/tmp/offshore-retirement-*`.

## Remaining upgrade validation

No physical device or authenticated CloudKit upgrade environment was available. The full test suite, cross-platform UI matrix, and notification-delivery integration were not run; focused regression tests and simulator builds were used for this removal.

Before release, install over a version with an active Excursion session and existing Marina history. Verify legacy monitored regions/significant updates stop, an existing Live Activity disappears, and pending/delivered purchase suggestions are removed while ordinary reminders survive. Verify assistant record deletions sync between devices, including records imported later from an older client, with financial counts/balances unchanged.

**Location usage descriptions, the location background mode, and Live Activity support remain temporarily** until that physical-device upgrade check succeeds. No feature start/request logic remains. Remove these declarations after validation; preserve CloudKit remote-notification support and shared app-group access.

Before rebuilding either feature, replace or disable its retirement cleanup. Otherwise new Marina records will be deleted and new Excursion sessions will be ended. Retained CloudKit-compatible definitions can be reused or extended deliberately.

## Documentation preservation mistake

Obsolete local Marina documents were deleted without a separate archive. They were ignored/untracked, so the source recovery commit does not contain them. Inspected Git history cannot restore most of them. Known affected paths include:

- `Docs/MarinaSemanticCapabilityMatrix.md`
- `Docs/MarinaNLArchitectureDiagnostic.md`
- `Docs/Marina/` (including the previously listed `MarinaCleanupAudit.md`)
- `Docs/MarinaUniversalPipeline/` (including the previously listed manual QA suite, QA findings, contributor guidance, and legacy ownership map)

The complete child inventory was not recorded before deletion. This affects local feature documentation, not financial data or the committed source checkpoint. A prior historical `MarinaCleanupCandidates.json` exists in Git history, but it is not a backup of the removed directories.

See `FeatureRetirementArchitectureGuide.md` for concrete Java-to-Swift and selective MVVM recommendations.
