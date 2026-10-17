# Marina rebuild: capability inventory and implementation contract

## Goal and scope

Marina helps users understand existing financial data in the current workspace through a natural, read-only conversation. Apple Foundation Models handles language and conversation; app tools retrieve records and calculate authoritative results. Existing creation buttons and forms remain available. Conversational mutation, Siri integration, cloud model providers, and a non-AI chatbot are outside this rebuild.

The replacement uses one conversation session and one read-only tool data path. Remove phrase repairs, custom semantic follow-up interpretation, competing legacy/universal routing, and the separate narration generation pass. Persisted history and financial services are separate concerns and must survive the replacement.

## Existing expectations recorded before removal

This inventory was derived from the old semantic prompt suite, manual QA matrix, query runner and formula tests, chat store tests, and creation service tests. These are behavioral expectations, not evidence that the live Apple model already understands every example.

| Capability | Representative requests and expected behavior |
| --- | --- |
| Workspace and inventory | “What workspace am I in?”, “How many cards do I have?”, “List my categories.” Return only the selected workspace’s objects. |
| Spending | “How much did I spend at Apple this month?”, “Show my biggest expenses”, “Show spending by card.” Support totals, lists, counts, averages, rankings, grouping, shares and comparisons. |
| Planned expenses | “What is my next planned expense?”, “How much planned spending do I have?” Distinguish expected amounts from recorded amounts and actual variable ledger activity. |
| Presets | “What do my presets add up to?”, “What is my recurring burden?” Report templates and their materialized costs without treating templates as ledger transactions. |
| Income | “How much income came in?”, “Show planned income by source”, “Compare actual income this month to last month.” Preserve expected/received semantics, source filters and progress calculations. |
| Budget health | “How much room do I have left?”, “What can I safely spend per day?”, “Am I spending too fast?”, “Does income cover my budget?” Preserve coverage, burn rate, projection and pace math. |
| Category limits | “Show category availability”, “Which categories are over limit?” Show period-scoped goals and over/near/under status. |
| Savings | “What is my savings balance?”, “Show my savings outlook.” Distinguish ledger balance, actual savings and projected savings. |
| Reconciliation | “What is Alejandro’s balance?” Preserve allocation/settlement signs and who owes whom; do not treat reconciliation balances as savings. |
| Spending scenarios | “What if I spend $50 today?”, “What happens to projected savings if I spend $200 on Groceries?” Explain hypothetical effects without writing records. Income replacement and savings-contribution scenarios were unsupported. |
| Conversation | “What about last month?”, “Actual only”, “Show more”, “What drove the increase?” Retain relevant context; a new standalone question must not inherit unrelated prior targets. |
| Ambiguity | Apple may refer to a merchant or card; Groceries may be a category or transaction description. Clarify competing matches, and never convert an unknown named target into an all-data answer. |
| Presentation | Explain metrics, comparisons, lists and empty results; retain supporting transaction drill-down where available. Increasing a page size must not change the full matching total. |
| History | Workspace-specific chats can be opened, named, cleared and deleted. Existing saved messages remain readable. |
| Creation UI | Preserve explicit forms for expenses, income, budgets, cards, presets and categories. These are separate from the read-only conversation. |

## Financial invariants

- All reads and record-ID validation are bound to the selected workspace in app code.
- Budget dates are inclusive. Budget planned rows use source budget ID, linked cards and dates.
- Planned actual amount zero means unrecorded; effective amount falls back to planned amount.
- Debit spending, signed ledger amounts and owned budget impact are different measures.
- Allocation shares and savings offsets reduce budget impact according to existing services.
- Savings balances derive from savings ledger entries. Reconciliation remains separate.
- Future planned and variable expense settings are independent; next-planned lookup remains able to find future rows.
- Nil categories remain virtual Uncategorized. Missing names and empty datasets must not produce fabricated matches or amounts.
- Tool detail pagination never truncates the dataset used for totals.

## Apple implementation guidance

Use the installed SDK’s actual availability declarations rather than assuming an iOS 27 capability exists. The initial replacement targets the Foundation Models APIs introduced in iOS 26 and works on later supported OS releases.

- [Generating content and performing tasks](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models): session lifecycle, instructions and responses.
- [Expanding generation with tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling): attach app functions to the session so the model can request app information.
- [Generating Swift data structures with guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation): typed generated arguments rather than parsing free-form text.
- [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window): bounded context and recovery when the session grows too large.
- [Adding intelligent app features](https://developer.apple.com/documentation/foundationmodels/adding-intelligent-app-features-with-generative-models): check model availability; device support, settings and assets matter in addition to OS version.
- [Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/) and [Deep dive into the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/301/): official implementation examples.

The app retains iOS 18 support, but Marina requires iOS 26 and an available model. An unavailable explanation replaces the former rule-based fallback. Model text is probabilistic; deterministic values and supporting records are produced by app code.

## Verification contract

Deterministic tests must cover workspace isolation, foreign/invalid IDs, financial math, ambiguity, empty results, pagination, saved-history compatibility, cancellation and chat/workspace switching. Shared Home calculations, creation forms and SwiftData schema must remain intact.

Real-model evaluation must exercise paraphrases and multiple turns with fixture data: merchant/card ambiguity, period refinements, biggest purchase, unrelated new income questions, and refreshed results following a UI edit. Check factual grounding and tool arguments, not exact prose. An evaluation that cannot run because a model/device is unavailable is not passing model coverage.

The previous suite primarily tested a rule interpreter or supplied handcrafted semantic requests. The previous opt-in live-model test covered only one spending interpretation and nonempty narration. Those tests did not establish conversational reliability. Preserve behavioral coverage at the tool boundary and evaluate the actual conversation path separately.

## Compatibility boundaries

Do not delete financial models, ledger entries, shared Home calculation services, workspace transfer formats or saved chat records. `MarinaChatSession` remains in the SwiftData schema. Old semantic fields and answer attachments may need compatibility-only decoders even after their execution code disappears. Keep stored history readable without executing obsolete follow-up requests. A bounded model context does not authorize deleting visible history.

Implementation validation results and known gaps must be reported with the change rather than inferred from this inventory.

## Implemented architecture

`Conversation/MarinaConversationController.swift` owns availability, turn serialization and stale-output protection. `MarinaConversationRuntime.swift` owns one Foundation Models session with native transcript context and streamed responses. It preserves results and asks the user to start a new chat after a context-window error. No phrase parser, semantic follow-up state or alternate query executor participates in this path.

`MarinaTools.swift` exposes five read-only tools with generated arguments: record resolution, expenses, income, budget summary and account ledgers. `MarinaReadOnlyDataService.swift` validates workspace IDs and filters and invokes existing financial helpers. `MarinaDataRequest.swift` and `MarinaDataResult.swift` form the deterministic boundary. Financial cards come directly from calculated results; model narration is separate and remains probabilistic. A competing-name lookup blocks financial reads for that turn until the person can clarify.

`MarinaPanelView`, `MarinaHost` and `HomeView` integrate the conversation and hide entry points below iOS 26. `MarinaConversationStore` preserves full visible chat history and treats old semantic payloads as opaque compatibility data. Existing creation forms and their service remain separate. The obsolete rule/hybrid interpreters, phrase repairs, semantic planners, dual/universal executors and their implementation-specific tests have been removed. Shared Home calculators and compatibility decoders remain.

The SwiftData schema and financial records have not been migrated or deleted. In debug builds, `MARINA_MODEL_EVALUATION=1` uses an in-memory app store so opt-in native model tests cannot open the user's saved budget.

## Verification performed — October 17, 2026

- App, widget and AppIntents compiled with the installed Xcode 27.1 SDK; Mac Catalyst test build succeeded.
- 123 tests across eight focused suites passed on iOS 26.3: read-only data service, conversation history, chat storage, budget formulas, creation service, Home query engine, savings and allocation ledgers.
- Added coverage for unequal calendar months, account selected-period activity, ambiguous-name read blocking, stable streamed evidence rows and closed-turn data access.
- Debug app installed and launched on iOS 18.6 with an isolated in-memory store. This verifies launch compatibility, not a full UI walkthrough.
- `git diff --check` passed. Removed runtime symbols have no remaining Swift references.
- Live model evaluation runs separately on the Apple Intelligence-capable Mac Catalyst host. It checks actual tool arguments and financial evidence, not exact wording. Earlier runs exposed skipped follow-up reads, invalid generated arguments and unrelated filter carryover. Passing deterministic calculations does not establish that model behavior is reliable.

Not yet covered: full device UI/accessibility walkthrough, broad multilingual/paraphrase model evaluation, long-conversation stress testing and the entire repository test suite. Those remain release checks; the focused run is not a claim of complete regression coverage.

At the initial rebuild checkpoint, live-model evaluation passed both scenarios (seven turns total): current card spending, previous month, largest purchase, unrelated workspace income, refreshed spending after inserting a purchase, ambiguous card/merchant clarification and the clarified merchant total. This was a real on-device Foundation Models run on Mac Catalyst, not a mocked interpreter. Earlier failures informed structured tool arguments and general tool-use instructions; no phrase-specific repair branches were added. This small evaluation is a regression baseline, not proof that arbitrary conversations will always be correct. The presentation work below changes the tool schemas and must be evaluated separately.

The last tool-boundary update also keeps invalid requests out of the “Verified budget data” label and displays their validation explanation. The deterministic bridge test checks that behavior.

To run live evaluation in Xcode, enable `MARINA_MODEL_EVALUATION=1` in the test action environment and run `MarinaLiveConversationTests` on an Apple Intelligence-capable destination. The tests intentionally fail if the model is unavailable; ordinary simulator regression runs leave these opt-in tests disabled.

## Native conversational presentation — October 17, 2026

New answers store an optional `MarinaPresentation` payload alongside narration. It preserves the executed operation, resolved scope, exact metrics, card appearance, expense snapshots, category colors and chart values. Older answers still use their existing renderer; no financial or chat migration is required.

`MarinaPresentationView` renders compact totals, `CardVisualView`, shared expense-row content, horizontal comparison/ranking bars, line trends and the existing donut component. These visuals are display-only. Direct pagination reloads a consistent prefix in increments of five using the saved workspace, dates, filters and calculation preferences; changed data updates the displayed values and count together. Snapshot values remain unchanged until an explicit refresh through pagination.

`MarinaPanelView` inserts the user message and assistant placeholder before awaiting the model. Streaming replaces that same answer identity. Inline status, Stop, and Retry preserve the submitted message, and chat changes cancel the old turn. Retry is offered for the latest failed turn so it cannot silently discard later conversational context. Narration uses native Markdown and primary text styling. New answers do not render legacy evidence rows or calculation-policy diagnostics.

The tool boundary preserves distinct result scopes. Successful empty results produce zero/empty presentations, while actual validation and generation failures have separate response states. Tool schemas use distinct generated names, and category rankings are an explicit operation that maps to grouped expense totals. Expense selections explicitly choose the whole workspace or matching filters: each named filter carries its identifier, combined filters remain supported, and empty matching selections are rejected. Name discovery returns these selections and remains internal except for inventory requests and ambiguity. These changes do not add a phrase parser or a second conversation engine.

On iOS 26.4 and later, Apple's native token-count API checks context before and after turns. A static composer footnote warns at 75% of capacity. At capacity or a framework context-limit error, new submissions stop and Start new chat saves the existing transcript before creating a chat in the same workspace. Earlier supported releases show the reached-limit notice when the framework reports exhaustion. The optional notice metadata survives reopening a chat; legacy history remains readable. This replaces silent near-limit rebuilding and automatic context-error recovery. Generic backend failures are checked against native token counts without parsing error prose, and successful visuals remain visible when narration fails.

Presentation verification includes exact `.38` amounts, multiple-card scope, empty categories, saved snapshots, legacy decoding, pagination after record edits, frozen future-expense preferences, comparison/trend/share data, stable message identities and schema-name collisions. The focused deterministic run passed 90 tests across seven suites. Rendering tests produced 24 fixtures across phone, tablet and large Dynamic Type/dark layouts; selected fixtures were visually inspected. Mac Catalyst and simulator builds succeeded. The updated app also installed and launched on iOS 18.6 with isolated in-memory storage.

Full interactive iPhone/iPad/Mac walkthroughs, VoiceOver navigation, Reduce Motion behavior, and deliberately delayed/cancelled responses during chat/workspace switching still require device-level verification. The message-state unit tests validate identity and persistence, not those complete UI interactions. Live model evaluation is recorded separately because correct app calculations and rendering do not prove correct model-selected filters.

### Current live-model acceptance status

The presentation implementation is not release-ready as a complete conversational feature. The latest targeted real-model run executed both long conversation scenarios and failed five assertions across those two tests:

- After listing a card's expenses, the model answered the largest-purchase follow-up without a fresh expense query, so no matching expense presentation was produced.
- A workspace income-total question selected a comparison instead of a summary. The amount was correct, but the resulting visual was not the requested presentation. The live test now explicitly checks this distinction.
- A category ranking in the longer chat supplied `EXPENSEWORKSPACE` as a category identifier. Validation rejected it; the expected ranking visual was absent.

The same run correctly scoped card totals and lists and returned the empty Hair Care category successfully, without a generation/context failure. Earlier runs of the current lookup/selection schema also passed the fresh-chat category/Hair Care and ambiguous card-versus-merchant scenarios. These successes do not override the failing long-conversation checks. Narration can still repeat amounts already displayed despite the concise-response instructions.

The failures are retained in opt-in regression tests, not bypassed by phrase repairs or an alternate query engine. Logs and assertions distinguish model-selected arguments from deterministic calculation and presentation results. Full acceptance remains open until tool selection, follow-up behavior and narration meet these scenarios reliably.

### Shared Home visuals and conversational presentation

Marina now uses shared snapshot-based content with Home's income progress gauge, spending trend bars/category rows, and Settings' preset rows. Budget pace reuses the progress gauge styling with spending-specific labels and the existing pace calculations. Home and Settings retain their navigation and editing controls; Marina's copies are display-only. Large Dynamic Type uses stacked metrics and preset details.

The native tools expose budget pace, income progress, and upcoming scheduled preset expenses as structured operations. Upcoming defaults to seven inclusive calendar days when dates are omitted, uses only generated unrecorded planned expenses, and preserves scheduled occurrences from archived templates. Model-supplied explicit dates remain explicit; the app does not repair them based on question wording. Ordinary expense queries continue to use expense rows, even when an expense originated from a preset.

Optional immutable presentation snapshots preserve income values, pace values, preset schedules/assigned-budget counts, and exact signed category contributions per trend bucket. Canonical presentation identities include workspace, financial scope, resolved dates, and calculation preferences. Saved answers retain suppressed result snapshots; optional suppression metadata hides identical same-topic visuals without changing tool execution. Changed results/topics, explicit visual requests, transaction lists, and errors remain visible. Identical tool results within a turn coalesce into one visual. This is display policy derived from saved answers, not a separate query or conversation engine.

Synthetic tests cover snapshot persistence, pagination refresh, unchanged/changed-result presentation, exact money, upcoming dates and archived presets, explicit card/workspace boundaries, missing pace baselines, ambiguous budgets, signed/category trend data, and older history. Rendering fixtures cover phone, tablet, and accessibility-size dark layouts. Interactive VoiceOver and full device walkthroughs remain manual acceptance work.

Live-model acceptance remains separate from deterministic UI/data correctness. Recent traces still select general budget overview instead of pace, occasionally choose income comparison instead of progress, and carry an earlier date range into upcoming presets or supply eight inclusive days. The live tests retain these distinctions, including explicit date-window assertions. No phrase repairs or alternate query engine were added to conceal these failures.

Verification for this pass: 95 focused deterministic tests across nine suites passed, including Home query calculations. The shared-rendering test generated 36 phone/tablet/large-text fixtures; selected preset, income, pace, and trend outputs were visually inspected, and the final large-text wrapping correction passed a further rendering run. Simulator and Mac Catalyst builds succeeded. Full interactive VoiceOver/device walkthroughs were not automated by these rendering checks.

The final real-model run executed two tests (the three-topic conversation and fresh-chat paraphrases) and failed five assertions: budget pace selected overview in both cases, the fresh income paraphrase selected comparison, and both upcoming queries supplied incorrect date windows. The conversation's income progress used correct actual/planned values. These failures remain release-acceptance blockers; the completed shared UI must not be described as proof of reliable model-selected purpose or date scope.
