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

`Conversation/MarinaConversationController.swift` owns availability, turn serialization and stale-output protection. `MarinaConversationRuntime.swift` owns one Foundation Models session with native transcript context and streamed responses. It rebuilds bounded visible exchanges after a context-window error. No phrase parser, semantic follow-up state or alternate query executor participates in this path.

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

The final live-model evaluation passed both scenarios (seven turns total): current card spending, previous month, largest purchase, unrelated workspace income, refreshed spending after inserting a purchase, ambiguous card/merchant clarification and the clarified merchant total. This was a real on-device Foundation Models run on Mac Catalyst, not a mocked interpreter. Earlier failures informed structured tool arguments and general tool-use instructions; no phrase-specific repair branches were added. This small evaluation is a regression baseline, not proof that arbitrary conversations will always be correct.

The last tool-boundary update also keeps invalid requests out of the “Verified budget data” label and displays their validation explanation. The deterministic bridge test checks that behavior.

To run live evaluation in Xcode, enable `MARINA_MODEL_EVALUATION=1` in the test action environment and run `MarinaLiveConversationTests` on an Apple Intelligence-capable destination. The tests intentionally fail if the model is unavailable; ordinary simulator regression runs leave these opt-in tests disabled.
