# Marina capability expansion

**Resumed at the user's request on October 29, 2026.** The [continuation checkpoint](MarinaContinuation.md) records the saved starting point. The latest validation below still leaves native conversational acceptance incomplete; earlier dated results are historical.

## Structured translation pilot — October 29, 2026

**Evaluation only; not enabled in the normal app.** `MARINA_MODEL_EVALUATION=1` together with `MARINA_QUERY_EXPERIMENT_MODE=compiled` selects the new Debug path. Existing uncommitted work, financial calculations, shared UI, and the normal production session/renewal path are preserved. There is no PCC dependency, phrase-based intent router, financial migration, or new write capability.

The first tool-free model step selects the intended answer and whether to start a question, change the active request, finish a pending clarification, or return to a supplied historical answer. The second receives a schema for that capability and proposes changes. A bounded proposed-answer description carries meaning forward as an unverified hint, never as source evidence. There is one shared repair allowance: only the failing stage retries, and patch/compiler feedback reaches the patch step without changing the selected goal. The app supplies known workspace state, calculates dates, resolves entities, compiles the request, executes the existing five read capabilities, and selects the primary result. The model does not choose tool names or orchestrate reads in this path. Narration remains a separate tool-free pass over verified evidence, with the existing visual and verified fallback preserved.

`MarinaTurnPatch` distinguishes keep, set, and clear. `MarinaRequestCompiler` preserves validated filters, financial measure, dates, metric, and chart intent while deriving operation-specific details. Category, card, and merchant ranking capabilities fix their grouping in app code. A budget supplying default dates remains distinct from a budget filtering expenses. Primary and comparison dates are frozen independently, including when either side needs a budget choice. Unknown or foreign references cannot turn into unrestricted reads, and every financial answer rereads current data through the shared execution boundary.

Completed canonical requests are stored on `HomeAnswer`; old conversations decode without this optional metadata. A bounded recent cache accelerates follow-ups, while metadata from older saved answers supports retrieval without replaying their financial contents. One pending clarification stores the original question, frozen request, unresolved targets, and typed candidates. Exact candidate replies revalidate current identities and fill the request directly. Pagination preserves pending choices and active context. Working memory is committed only after a valid clarification or a saved completed financial frame; failed, cancelled, or oversized turns preserve the prior state.

The main new files are `MarinaCapability.swift`, `MarinaTurnPatch.swift`, `MarinaRequestCompiler.swift`, `MarinaRequestTranslator.swift`, `MarinaCompiledTurn.swift`, and `MarinaFrameRetrieval.swift` under `CoreViews/Home/Marina/Conversation`. Integration changes are in the existing runtime, memory, data service, tool bridge, answer model, and pagination fallback. The compiler and execution tests are separate from native acceptance tests so valid calculations cannot mask misunderstood questions.

**Promotion and capability expansion remain gated on native acceptance.** The catalogue maps existing report capabilities, but mapping them is not evidence that the model can select them reliably. The pilot must pass critical sequences three times, including held-out wording and restored conversations. Unsupported or ungrounded changes remain errors; guards must not be weakened to make native tests pass. See [the diagnostic instructions](MarinaManualTokenTesting.md#compiled-translation-and-longer-chat-acceptance) for evaluation flags and suites.

### Final compiled-pilot validation — October 29, 2026

The final source builds for Mac Catalyst and the iOS 26.3 simulator. The focused Mac run passed **399 tests across 35 suites**. The simulator passed **398 tests**, with the native token-count benchmark intentionally skipped, across the same 35 suites. Coverage includes canonical request inheritance/clearing, independent date choices, scope validation, cancellation, atomic frame saves, persisted older answers, pending pagination, stage-specific repair, financial parity, presentation, and narration focus. An explicit `.total` no longer replaces a ranking, highest/lowest expense, or comparison answer with the whole-dataset total. Ordinary totals, counts, and averages retain their meanings.

**Native acceptance failed.** Tests ran on macOS 27.2 (26B123), using Xcode 27.1 and the available on-device model reporting an 8,192-token capacity. Counts below are parameterized cases, not individual assertions:

| Native suite | Final result |
| --- | --- |
| Original `MarinaCapabilityLiveTests` | 15 passed, 34 failed out of 49 executed cases; 2 unrelated older experiment functions remained gated/skipped |
| New `MarinaTranslationLiveTests` | 3 passed, 15 failed out of 18 repeated cases |
| `MarinaTranslationLongConversationTests` | All 20 turns attempted; correctness failed, including the reopened earlier-report/changed-data answer |

In the original matrix, direct category availability, greeting/workspace summaries, and chronological line charts each passed 3/3. Category comparisons, the card summary/extrema/merchant sequence, spending patterns, warning filters, broad clarification followed by the chosen topic, merchant narrowing/restoration, and card grouping failed their repeated flows. Five of twelve metric cases and one of three transaction/next-expense cases passed. The new availability family passed 3/3, but its comparison, card sequence, grouping, held-out, and compound-request families failed 3/3. Different wording/fixtures can therefore produce different outcomes for the same capability.

The remaining problems are semantic interpretation: modifiers or dates become entity names, explicit card scope can be omitted, topic changes retain incompatible fields, and follow-up/comparison intent is lost. Some wrong requests produce a completed answer or a safe not-found clarification. `completed=true` is not acceptance, and coincidentally matching amounts do not validate scope. The guarded compiler rejects invalid sources/types instead of repairing them by broadening the read. The selected capability and the final financial request must both be checked.

There were no logged translation input-budget or context-exhaustion failures in the final native sweep. The 20-turn test forced the app's budget to 4,096 tokens; the host's model remained the 8K model. Native schema checks include full schemas, instructions, references, the question, a maximum-length interpretation hint, and the unchanged 1,024-token reserve. Selection input was 1,330 tokens; full patch inputs ranged from 1,068 to 2,846. Reusing shared schema definitions reduced the comparison input from 3,075 to 2,618 without changing fields or weakening constraints. Actual translation inputs in the acceptance sweep reached 2,584 tokens.

The 68 new-suite/endurance turns had a median total latency of 5.54 seconds and a maximum of 11.45 seconds, including failed turns and clarifications; this is not a successful-answer speed comparison with production. Fourteen turns reported narration fallback for validation. Other turns often failed before narration, so they must not be counted as successful generated financial explanations.

Physical supported 4K-device testing and a live VoiceOver pass were not available in this run. Simulator testing does not exercise Apple's native model, and forced budgeting does not establish accuracy on another model/device. No new layout was introduced in this pass. Capability expansion remains deferred and the compiled path remains disabled by default.

Final logs are `/private/tmp/marina-compiled-acceptance-build.log`, `marina-compiled-acceptance-deterministic.log`, `marina-compiled-acceptance-native.log`, `marina-compiled-acceptance-simulator-build.log`, and `marina-compiled-acceptance-simulator-tests.log`. The native result bundle is `~/Library/Developer/Xcode/DerivedData/OffshoreBudgeting-asvgheyvpdmuaobjjntzlgxdpmdr/Logs/Test/Test-OffshoreBudgeting-2026.10.29_13-02-21--0700.xcresult`; its extracted summary and case tree are `/private/tmp/marina-compiled-acceptance-native-summary.json` and `marina-compiled-acceptance-native-tests.json`. Earlier `marina-compiled-*` logs describe intermediate implementations, not the final result.

The existing capability foundation keeps the five read tools and the on-device model. Queries resolve names inside the selected workspace and fetch current financial records on each turn. That work adds structured report purposes, metric focus, saved context, evidence-bound narration, and optional report snapshots that older saved conversations can omit.

## Capability map

| Tool | Added answers |
| --- | --- |
| `readExpenses` | Complete card spending, highest and lowest positive expenses, ordered category/card/merchant rankings, counts and averages, category shares, independent period leaders, scheduled next expense, transaction kind/split/offset/provenance, spending patterns and peak contributors |
| `readIncome` | Counts, averages, and separate planned/received timelines |
| `readBudgetSummary` | Complete income/expense/savings components, actual/projected/Max Savings, category availability and minimum goals, status filters, linked cards/presets, cumulative savings and progress |
| `findRecords` | Existing workspace-scoped resolution; selected workspace references and combined category selections remain explicit |
| `readAccounts` | Existing savings and reconciliation reads remain separate |

`MarinaDataRequest` carries the requested metric and operation independently. `MarinaReport` carries verified supporting facts to the model and saved visual. Counts, extrema, shares, averages, period peaks, and cumulative values are calculated before pagination. The optional report fields preserve decoding of older snapshots.

An omitted date uses the sole active budget's inclusive dates, then Home's range, then the configured period. Overlapping active budgets require a choice. `periodBudgetID` supplies dates; `budgetID` also applies the budget's financial filters. Follow-ups freeze resolved dates and keep validated targets. Category selections are a union.

## Financial definitions

- Card summaries match Card Detail: debit spending plus effective planned expenses.
- Budget details preserve distinct planned, recorded, effective, and variable expense components. Budget planned expenses require the selected budget's source ID, linked cards, and date window. Budget income remains workspace income in the period.
- Max Savings is planned income minus effective planned expense impact, matching Budget Detail.
- Actual savings includes manual savings adjustments. Home's cumulative savings chart and Marina use the shared `SavingsOutlookCalculator`. Progress retains its real ratio; only the gauge clamps to its visual range.
- Positive expense extrema exclude credits/zero-impact adjustments unless a signed ledger measure is explicitly requested. Transaction details preserve original charge, recorded/effective amount, splits, reconciliation offsets, savings offsets, and budget impact as distinct facts.
- Home-style next planned expense can already have a recorded amount. Upcoming preset occurrences remain unrecorded generated expenses. Neither operation establishes an unpaid obligation.
- Planned and received income never form one combined timeline. Cumulative savings begins with period cash flow, not the savings account balance.
- Calculation policy reports only supplied future-expense settings and actual exclusions. It does not infer screen-local display settings.

No financial-record migration, deletion, conversational write, expanded What If scenario, or unrelated screen redesign is included.

## Conversation and narration

The conversation uses a focused tool-selection step followed by a tool-free narration step. A compact evidence catalog binds each financial proposition's subject, relation, value, and scope. Validation rejects invented references, values, dates, reversed directions, and unsupported interpretations. Failure retains successful visuals and uses a question-specific verified explanation. Generation schemas are included explicitly, and their cost is part of context accounting.

The target is answer-first prose: one or two sentences for a focused question, a brief breakdown for summaries. A greeting introduces Marina; a broad assessment asks the user to choose spending, limits, income, or savings. Explicit workspace summaries read the workspace overview. Tests assert essential facts and scope rather than exact model wording.

Marina reuses Offshore's existing display components. Spend Trends defaults to Home's category-colored bar chart. A request to examine movement over time can select the shared line chart through structured chart intent; this changes presentation, not whether values are cumulative. The compact overview retains the total, peak period, and up to three category and merchant highlights. Detailed contributions, frequency rankings, and period values remain available through expansion. Exploratory reads do not each become a full report.

The selected workspace is app-bound context, not a name the model must rediscover. Offered merchant choices retain canonical identities through clarification, pagination, and saved-chat restoration. Selecting one uses an exact merchant filter; partial discovery continues to search for possible choices. Stored merchant descriptions are not renamed or merged.

The staged sessions apply Apple's [context-window guidance](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window) and [guided-generation walkthrough](https://developer.apple.com/videos/play/wwdc2025/259/). The query outcome contains an action and up to three constrained result references, with the primary result first. Financial answers require a current verified result. Unused references may be discarded only for a conversational action with no tool results and no financial-read requirement. Narration chooses among constrained evidence references and can supply a neutral prefix; the app inserts the complete verified subject, relation, value, scope, and sentence ending. Its instructions cover only the already-selected action, and financial explanations cannot generate an opening greeting.

Schema validity and financial validity remain separate checks. Entity selections use the framework's plain string schema with strict syntax, fresh reference, and workspace validation. Experimental pattern guides were rolled back after native incompatibilities and malformed tool generation; the latter does not establish regex causality. Native testing rejected Swift-valid anchors and custom character classes, consistent with [Apple's documented pattern limitation](https://developer.apple.com/forums/thread/792827). Result/evidence references and collection bounds retain actual generation constraints.

A pending choice is app state. A type-only narrowing reply refreshes the offered choices directly. An exact choice is revalidated against its canonical identity; a complete saved request can then resume without asking the model to rediscover the name. When the saved request is incomplete or the user changes the question, the focused query step receives the original question and confirmed choice. A simultaneous successful lookup for another target must not erase unresolved candidates.

The peak-period transaction button opens a read-only sheet with fresh records. It preserves the saved report's period, scope, measure, and future-expense policies, including while paging. A changed total is identified; removed filters produce an explanation. Reading the sheet does not replace the report or conversation memory.

## Shared scenarios and text-only QA

`OffshoreBudgetingTests/MarinaCapabilityScenarios.swift` is the shared scenario registry used by deterministic bridge checks and native evaluations. Each row below starts a **new chat**. Arrows stay in the same chat. Use a workspace with distinct period/category winners, a card with multiple expenses, and category limits near and over their maxima. Native fixtures use an injected October 17, 2026 clock; manual testing should record the real period displayed.

| Scenario | Prompt sequence | Essential checks |
| --- | --- | --- |
| Category comparison | “What is my top category this period?” → “What about in June? Can you compare?” | First answer names the top category and amount. Comparison names each period's winner, both periods/amounts, and calculated difference. |
| Card follow-ups | “Summarize my Apple Card for this month.” → “What was the highest expense on the card this month?” → “And the lowest?” → “Where do I spend the most money on my Apple Card?” | Complete card breakdown; highest then lowest positive expense; last turn ranks merchants. Card, date range, and measure remain consistent. |
| Spending patterns | “What are my spend trends?” | Trend, leading categories, merchant amounts/frequency, peak period and contributors. |
| Category warnings | “What categories are over their limit or nearing their limit for this month?” | Only requested statuses, budget supplying limits, spent/available/percentage and counts. |
| Availability | “Show category availability” | Category report, including goals and planned/variable contributions. |
| Broad assessment | “How am I doing this month overall?” → “Spending patterns, please.” | Brief clarification, then the selected report. |
| Greeting | “Hey, Marina!” → “Summarize my Personal workspace.” | Warm introduction, then a real scoped overview without trying to resolve Personal as a card/merchant. |
| Merchant clarification | “Show DoorDash expenses on Apple Card for October 2026.” → “The merchant, please.” → reopen the chat → “DoorDash - BevMo!” | Offered punctuated choice remains selectable; only that merchant on Apple Card in October is included. A longer similarly named merchant and the same merchant on another card are excluded. |
| Card grouping | “Break down my October 2026 spending by card.” | A card breakdown with each card's amount, distinct from merchant clarification. |
| Temporal progression | “Plot how my Apple Card spending changed week by week in October 2026.” | Shared chronological line chart, original card and dates, period totals rather than unsolicited cumulative values. |

Repeat each critical chat three times. Rerun failures after a fix. Add held-out wording, a topic change, a budget-choice clarification, and reopen a saved chat before asking “And the lowest?” Compare a specifically named category across periods separately from comparing each period's winner.

Additional metric checks: actual/projected/Max Savings; category minimums; count/average/share; linked cards and presets (including archived/missing-card cases); next planned expense; refunds, adjustments and shared purchases; paired income; cumulative savings and progress beyond 100% or below zero. Include empty activity, ties, uncategorized expenses, final-day entries, overlapping budgets, manual savings adjustments, and independent future-expense preferences.

For each turn record:

```text
Scenario / repetition:
Fresh chat or follow-up:
Question:
Expected target / period / metric:
Answer facts correct: yes / no / unsure
Visual appropriate: yes / no
Default report compact; expanded details available: yes / no
Natural and directly answers the question: yes / no
Actual result or error:
MarinaTokens report (if enabled):
```

## Verification

### Resumed implementation — October 29, 2026

The resumed pass fixes additional contract defects found in native and independent review:

- Only eligible financial answers or explicit inventories receive `qN` answer references. Name discovery still supplies `rN` entity selections. Lookup and rejected-read outputs cannot advertise answer references that selection later rejects.
- Missing-target repair feedback preserves the complete combined selection instead of alternating between a merchant and a card.
- Repeated canonical expense selections inherit omitted scope, measure, future policy, transaction filter, and chart intent. Explicit arguments override those defaults; different selections and intervening financial topics remain independent.
- Period comparison scope equality includes canonical category sets. Type-only clarification does not choose an earlier candidate when a different name is supplied; explicit date adjuncts remain supported.
- Home's existing projected savings line and Marina timelines now share `HomeFinancialLineMark`. Home retains its signed actual bars and dashed projection. Financial calculations are unchanged.

Mac Catalyst builds passed. **316 focused tests across 27 suites passed**, including the new reference/context regressions, rendering, native schema calibration, and experiment safeguards (`/private/tmp/marina-mac-final-tests.log`). An intermediate guide expansion exceeded the conservative 4K startup budget; repeated descriptions were removed without reducing the reserve.

The initial resumed native smoke completed and exposed the answer-reference and combined-selection feedback defects. A later native run using shortened instructions was interrupted after it exposed repeated card-summary operations on extrema follow-ups. The instruction to change the operation/metric while preserving scope and dates was restored. Neither intermediate run establishes acceptance of the final source.

The completed production-mode matrix (`/private/tmp/marina-resume-native-final.log`) ran **49 cases across 14 test functions**: **12 cases passed, 37 failed**, with 112 failed assertions across 72 turns. It ran on macOS 27.2 (26B123), Xcode 27.1 (27A9275), default on-device `SystemLanguageModel`, capacity 8192; no separate model revision is exposed. This run preceded the additional single-card contract check described below.

| Native scenario | Passed cases |
| --- | --- |
| Top category → June comparison | 0 / 3; initial top-category answers were correct, comparisons failed |
| Card summary → highest → lowest → merchant | 0 / 3 |
| Compact spending patterns | 1 / 3 |
| Over/near category limits | 0 / 3 |
| Direct category availability | 0 / 3 |
| Greeting → workspace summary | 1 / 3 |
| Broad assessment → spending | 0 / 3 |
| Additional metrics | 3 / 12: actual savings, linked cards, category share |
| Transactions / next planned expense | 1 / 3: next planned expense |
| Restored highest → lowest | 0 / 1 |
| Held-out comparison / cheapest / availability | 0 / 3 |
| Merchant narrowing and restored exact selection | 3 / 3 |
| Expenses grouped by card | 0 / 3 |
| Temporal progression using period lines | 3 / 3 |

All 55 attempted narration generations used the verified fallback. Median query time was 12.99 seconds (0–37.62, including app-resolved choices); median narration time was 1.71 seconds. Successful results still sometimes used the wrong operation, grouping, period, or metric. Financial grounding is not conversational acceptance.

Final production schema calibration passed: tools 2704, initial transcript 2843 (fallback estimate 2853), query schema 137 (estimate 147), prefix plus query schema 2980 before the question (`/private/tmp/marina-mac-final-tests.log`). Counts overlap; do not add tool definitions to the transcript count. Physical 4K-device conversations remain unverified.

The iOS 26.3 simulator exposed different valid schema serialization: local references and unions of singleton enums. Assertions now inspect the constraints on the actual fields, resolving local references and rejecting unconstrained alternatives, instead of requiring the newer flattened JSON layout. It also exposed a four-token overrun in the conservative 4K startup check. Removing the contradictory instruction “Charts only when requested” restored the margin while preserving the reserve and default chart behavior. Simulator rendering found truncated large-text merchant/peak headings and contribution text; they now wrap.

The final simulator app/test build passed, and **379 tests across 30 suites passed** (`/private/tmp/marina-simulator-text-final.log`). This includes the focused Marina suites, Home query regressions, and Home category/next-planned/spending-trend helpers. The latter three suites are excluded by the default test plan; only those exclusions were removed in a temporary test manifest, with no project-plan change. Phone, tablet, and accessibility3 dark-mode fixtures were rendered; the final large-text pattern view was visually inspected and copied to `/private/tmp/marina-final-renderings`. The last text-wrapping adjustment also passed the Mac Catalyst build and both rendering tests (`/private/tmp/marina-mac-text-build.log`, `/private/tmp/marina-mac-text-render.log`); these overlap the focused test count above. Rendering checks do not exercise live VoiceOver navigation, which remains outstanding, as does a physical 4K-context device pass. An initial failed simulator run completed its assertions but stalled collecting diagnostics and was terminated; subsequent runs completed with verbose failure-diagnostic collection disabled.

The card-grouping failure exposed a further semantic contract issue: the model used `cardSummary` for a workspace-wide grouped request. Tool-level validation now requires a selected card for `cardSummary`, with repair feedback distinguishing `cardTotals` from a combined `summary`. The underlying data service and older saved snapshots remain compatible. **The production-mode rerun passed all three card-grouping cases** (`/private/tmp/marina-resume-card-grouping.log`); all three narrations still used verified fallback. This targeted rerun is separate from the earlier full matrix, not a new full acceptance pass.

The **latest production-mode smoke**, after the chart-instruction correction, completed 12 cases across four test functions (`/private/tmp/marina-native-platform-final.log`): category/June comparison **0/3**, Spend Trends **2/3**, card grouping **1/3**, and temporal lines **3/3**. It reported ten failed assertions across 15 turns; all 12 narration attempts used fallback. Median query time was 16.41 seconds (5.79–30.77); narration median was 1.54 seconds. Card grouping's earlier 3/3 is therefore not a stable acceptance result. The failed final card-grouping cases never reached an expense read; comparisons still selected the wrong operation or failed generation/selection. Successful financial data and grounded fallback prose do not establish that the model answered the requested question.

#### Controlled query experiments

The app's default five-tool behavior is unchanged. Debug-only experiments compare fresh query context with all five tools against the same fresh context plus a tool-free semantic domain selector. Both retain validated memory, visible history, reference validation, fresh reads, and the existing retry allowance. These are explicit evaluation flags, unavailable in Release; see [the diagnostic instructions](MarinaManualTokenTesting.md#october-29-controlled-query-experiments).

The matched native tests cover category/June comparison, card extrema/merchant/topic changes, direct availability, and card grouping, each repeated three times:

| Experimental mode | Category comparison | Card sequence | Availability | Card grouping |
| --- | --- | --- | --- | --- |
| Fresh context, all five tools | 0/3 | 0/3 | 0/3 | 3/3 |
| Fresh context, semantic tool subset (final descriptions) | 0/3 | 0/3 | 0/3 | 0/3 |

Logs: `/private/tmp/marina-query-fresh.log` (39 failed assertions) and `/private/tmp/marina-query-semantic-final.log` (45). Median query times were 11.79 and 6.64 seconds; semantic routing added a median 0.48 seconds. All 22 and 17 narration attempts respectively used fallback. Early failed prerequisites can prevent later turns within a case; both runs completed all 12 parameterized cases. The initial, shorter classifier descriptions also failed all 12 end-to-end cases (`/private/tmp/marina-query-semantic.log`, 60 assertions).

The separate held-out classifier evaluation completed **117 classifications, 93 correct** (`/private/tmp/marina-query-routing.log`, median 0.359 seconds). It confused budget-linked cards/presets with inventories, omitted part of a mixed request, and retained the pending spending domain on an explicit income topic change. Several other mismatches chose `mixed`, which safely restores all tools but does not satisfy exact routing acceptance. Passing isolated classification does not establish correct query selection.

These results do not support enabling either strategy in production. A smaller toolset reduced latency but did not reliably select operations or preserve the intended answer. Reverting to the earlier flat optional-comparison schema is also not supported: prior native logs show it inventing comparison payloads for ordinary reports and then changing the operation during repair. Keep the experiments reproducible without treating their presence as a product fix.

### User-requested checkpoint — October 28, 2026

The saved source compiles for Mac Catalyst, and **304 tests across 26 suites passed**, including focused deterministic regressions and native schema/token calibration. The conservative 4K startup check also passed. See [the continuation checkpoint](MarinaContinuation.md) for commands, source decisions, and remaining work.

Native conversational acceptance remains unfinished. The last completed smoke used a superseded query schema: greeting/workspace summaries passed 3/3; the card sequence completed but chose the wrong measure and merchant operation; patterns selected the wrong final action. The saved same-selection measure fix and restored flat query outcome passed deterministic tests but have not yet been rerun conversationally. Final simulator testing and live VoiceOver navigation are deferred to continuation. No commit was made.

### Verification approach

Focused deterministic suites cover data calculations, tool translation/reference validation, saved memory, narration validation, snapshot compatibility, and shared savings calculations. Rendering fixtures cover phone/tablet widths and accessibility text sizes. Native `MarinaCapabilityLiveTests` is opt-in with `MARINA_MODEL_EVALUATION=1`; disabled tests are not conversational passes. `MarinaToolSetBenchmarkTests` uses `MARINA_SCHEMA_BENCHMARK=1` for native schema/context measurement. See [token testing](MarinaManualTokenTesting.md) for diagnostics setup.

The implementation is present, but native conversational acceptance is not complete. A verified financial result can still answer the wrong question when the model chooses the wrong operation or period. Evidence validation prevents unsupported narration; it does not establish that the chosen query matches the user's intent.

### Implementation areas

- Request/result contracts, query execution, reference validation, saved context, tool schemas and evidence narration: `OffshoreBudgeting/CoreViews/Home/Marina/Conversation/`.
- Availability, group breakdowns, transaction details and paired timelines: `OffshoreBudgeting/CoreViews/Home/Marina/Surface/`.
- Shared headline/timeline calculations: `OffshoreBudgeting/Services/SavingsOutlookCalculator.swift`, used by Marina and the Home Savings Outlook tile/metrics view.
- Large-text category rows: `OffshoreBudgeting/HomeWidgets/Categories/Availability/CategoryAvailabilityRowView.swift`.
- Scenario registry, deterministic financial fixtures, native acceptance, narration and report rendering: the `MarinaCapability*`, `MarinaNarrationValidationTests`, `MarinaReportPresentationTests`, `MarinaPresentationRenderingTests`, and `SavingsOutlookCalculatorTests` files in `OffshoreBudgetingTests/`.

### Validation record — October 27, 2026

- Focused simulator run: 271 tests passed, eight opt-in long native tests skipped. Xcode's headline of 279 includes those skips; parameterized rendering produces 273 passing executions. This is not a 279-test native pass.
- Existing Home query regressions: 56 passed. Additional category, next-planned-expense and spending-trend helpers plus rendering: nine test functions passed.
- Simulator app/test build and Mac Catalyst build-for-testing passed. The app build also compiles its widget extension and AppIntents. No storage schema changed.
- Rendered phone, tablet and accessibility3 dark-mode fixtures; inspected expanded category names, budget-source labels, metrics and paired savings. Fixed clipped labels. Live VoiceOver navigation and a physical 4K-context device remain untested.
- The startup budget test includes the complete user prompt/fresh-read reminder and the response contract. All five tools remain registered. The typed narration response contract is included once in session instructions (`includeSchemaInPrompt: false`); benchmark output separately reports the omitted schema's token count. Tool output keeps compact evidence and calculation policy; saved presentations retain the full report.
- Native acceptance is run separately on the Mac's on-device model with an injected clock and synthetic in-memory finances. Each original critical chat is repeated three times. Additional metric and transaction cases are independent, so a failed generation does not skip the remaining capability families.

The last native runs produced these outcomes. A chat passes only when its operation, scope, period, visual and essential answer facts meet the assertions; a correct number inside an unrelated overview is insufficient.

| Native scenario | Passed repetitions/cases |
| --- | --- |
| Top category followed by June comparison | 0 / 3 |
| Card summary, highest, lowest, merchant sequence | 0 / 3 |
| Spending patterns | 0 / 3 |
| Categories over or near their limits | 0 / 3 |
| Direct category availability | 1 / 3 |
| Greeting followed by workspace summary | 3 / 3 |
| Broad assessment followed by chosen spending report | 3 / 3 |
| Additional metric families | 1 / 12; paired income passed |
| Transaction details and next planned expense | 1 / 3; split purchase details passed |
| Restored highest-to-lowest follow-up | Failed: period end changed |
| Held-out leader/cheapest/category-room wording | 1 / 3; category room passed |

The complete native run reported 79 failed assertions; the isolated availability rerun reported eight. These are assertion counts, not unique defects. The category chats were separated into their own tests afterward so an earlier failed trend assertion cannot suppress their execution. The eight older long-conversation native tests were not rerun in this pass; current critical native failures remain unresolved, and the focused suite already exercises a restored chat separately.

Native context measurement passed: all five tool definitions occupied 2,569 tokens; the initial session transcript including instructions occupied 2,906 (the conservative fallback estimated 2,925). The separately measured narration schema was 211 tokens and is not duplicated in the prompt. The Mac model's context capacity was 8,192. The 4K startup check passes, but its narrow headroom is not evidence of reliable full conversations on a physical 4K device.

Do not treat the expansion as conversationally accepted until the original native scenarios pass. Observed failure families include incorrect report/metric selection, losing comparison focus, invented partial-period dates, failed follow-up scope, and tool retry limits. Generated financial drafts also often ignore the literal-slot contract and correctly fall back to verified prose. These failures require general routing/schema/model-contract work, not additional exact-phrase rules. Expanded What If support remains deferred.
