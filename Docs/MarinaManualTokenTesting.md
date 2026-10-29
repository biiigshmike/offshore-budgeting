# Marina context management, diagnostics, and manual testing

Marina now keeps the saved conversation separately from the model's bounded working context. All five production tools remain available. Reports use **format 4**. The October 17 section below records the historical, unmodified baseline; the October 23 implementation changes instructions, tool schemas, model-facing facts, and context management while preserving financial calculation services and saved financial presentations.

## October 28 staged-query revision

Current behavior and acceptance results are recorded in [MarinaCapabilities.md](MarinaCapabilities.md). Older dated measurements below describe their respective implementations, not the current model contract.

The query session keeps all five tools and returns bounded result references. A separate, tool-free session composes the explanation from the selected verified evidence. Both explicitly include generation schemas, including after renewal and restoration. `MarinaPhases` records query/narration duration, selected references, narration input/schema cost, and fallback reason in opt-in native evaluations. Query transcript counts do not include the separate narration session; do not add overlapping component counts to either transcript.

Comparison tool arguments now carry their second selection and dates inside the operation payload (`compare` or `compareIncome`), so a simple operation does not also generate a speculative comparison. Result references and narration evidence references have real generation constraints; all entity references are decoded and checked against fresh workspace data.

Native capability testing uses `MARINA_MODEL_EVALUATION=1` with synthetic in-memory finances. Add `MARINA_LONG_EVALUATION_VERBOSE=1` for fixture tool arguments and mapped requests, and `MARINA_SCHEMA_BENCHMARK=1` for schema calibration. Raw fixture logging requires both evaluation and verbose flags. Do not enable these flags for manual testing of a real workspace; use ordinary token diagnostics there.

## October 29 controlled query experiments

The normal app still uses the production five-tool query session. Debug-only experiments additionally require `MARINA_MODEL_EVALUATION=1` and an explicit `MARINA_QUERY_EXPERIMENT_MODE`:

- `production` (also the absent/invalid value): unchanged session behavior and all five tools.
- `fresh`: rebuild query context every visible turn from validated memory and bounded visible history, keeping all five tools.
- `semanticTools`: the same refresh behavior, plus a separate tool-free domain classifier that selects among the existing tool implementations. Mixed/failed classifications retain all tools; existing bounded repairs can broaden once without adding a retry.
- `compiled`: evaluation-only two-step translation. The first tool-free session selects an answer capability and new/active/pending/earlier context. The second receives only that capability's optional change schema. Ordinary app code compiles the request, resolves identities, executes the existing read implementation, and selects the result. A separate tool-free narration session still uses verified evidence.

`MarinaQueryExperiment` logs mode, domain, routing latency/input/schema tokens, effective tool names, and fallback reason. Query timing excludes the separate routing phase. Selected tool schemas remain part of query context accounting. The classifier receives the pending original question separately from compact memory, so memory trimming cannot silently erase it.

The two `freshQueryExperiment…` tests in `MarinaCapabilityLiveTests` also require `MARINA_QUERY_RENEWAL_EXPERIMENT=1`; run the same tests in both modes. `MarinaQueryRoutingLiveTests` requires `MARINA_QUERY_ROUTING_EVALUATION=1` and independently checks held-out domain selection and clarification/topic changes. Classifier passes do not establish correct financial queries. Keep failed classifications and full conversation failures in the report, including successful reads that answer the wrong question. See the dated results in [MarinaCapabilities.md](MarinaCapabilities.md).

### Compiled translation and longer-chat acceptance

Use `MARINA_MODEL_EVALUATION=1` and `MARINA_QUERY_EXPERIMENT_MODE=compiled` together for synthetic native tests. `MarinaTranslationLiveTests` repeats the category/June comparison, card summary/extrema/merchant sequence, availability, card grouping, held-out wording, and compound-request handling three times. Also rerun `MarinaCapabilityLiveTests` for the original metrics, greetings, workspace summaries, charts, and merchant-choice regressions.

Add `MARINA_TRANSLATION_LONG_EVALUATION=1` for `MarinaTranslationLongConversationTests`. It attempts all 20 turns with a forced 4K budget, saves/reopens the actual chat store, returns to an older report, changes fixture transactions, and checks fresh results. A completed turn is not an acceptance pass: assertions inspect operation, scope, dates, visuals, and facts. Actual supported 4K-device testing remains separate from this forced-budget run on the Mac.

`MARINA_SCHEMA_BENCHMARK=1` enables the translator's native schema measurements. It counts the full capability-specific schema used by the runtime, along with instructions, references, question, and the unchanged response reserve. Pruned-field measurements are diagnostic comparisons, not the runtime contract. `MARINA_LONG_EVALUATION_VERBOSE=1` additionally logs fixture-only generated JSON. Do not enable synthetic evaluation flags against a real workspace.

The app stores completed requests on historical answers and keeps a bounded recent cache. Translation uses the active request, one pending clarification, relevant earlier request descriptors, and a bounded recent exchange; it does not replay the entire financial transcript. Both interpretation sessions are fresh each turn. The normal production path retains its existing session renewal. Exact offered choices can resolve directly, without interpretation calls. Failed/cancelled turns cannot commit working memory, and pagination cannot replace a pending question.

Keep this path experimental until the critical native conversations pass three repetitions. Capability mappings and deterministic tests do not establish model reliability. Record interpretation failures, clarification failures, narration fallback, input/schema cost, latency, and OS/model capacity separately.

## Enable reports in Xcode

1. Open the project in Xcode and select the main **OffshoreBudgeting** scheme and your Apple Intelligence device or My Mac (Mac Catalyst).
2. Choose **Product → Scheme → Edit Scheme → Run → Arguments**.
3. Under **Environment Variables**, confirm `MARINA_TOKEN_DIAGNOSTICS` has value `1` and its checkbox is enabled. The shared Run scheme supplies this setting.
4. Leave `OS_ACTIVITY_MODE=disable` unchecked. Leave the old semantic trace disabled.
5. Run the Debug app from Xcode, open Marina, and show the debug console with **View → Debug Area → Activate Console**.
6. Filter the console by `MarinaTokens`. Initialization prints `MarinaTokens diagnostics enabled`.
7. After each answer, failure, or cancellation, wait for its complete report. Copy from `BEGIN REPORT` through `END REPORT`, including every intervening line.

These diagnostics are Debug-only and require the exact environment value `1`. They do not run in Release builds. If no reports appear, confirm the scheme and Run configuration, stop and relaunch from Xcode, and reopen Marina. Token measurement requires Apple's supported OS/API; unsupported counts read `unavailable`, not zero. An unavailable count is useful diagnostic evidence—include it.

Reports contain temporary correlation identifiers, token counts, timings, fixed operation/status labels, and filter-presence flags. They omit your question, record names, financial values, actual dates, persistent record identifiers, and raw tool/framework output. Question wording and screenshots are optional.

## Scenarios

The capability expansion adds a [shared scenario matrix and text-only QA guide](MarinaCapabilities.md#shared-scenarios-and-text-only-qa), including the original category, card, availability, greeting, and follow-up cases. Keep each scenario in its own chat.

Use the same workspace and settings throughout a comparison. Names below are examples: use a real card/category from your workspace. Start a new chat where indicated.

1. **Workspace timing, fresh chat:** “What workspace am I in?” Then, in the same chat, “And which workspace are we using now?”
2. **Spending conversation, fresh chat:** “How much have I spent this month?” → “And how much of that was on my Apple Card?” → “Show me the expenses included in that total.” → “Which purchase was the biggest?”
3. **Empty category, fresh chat:** “What did I spend on Hair Care this month?” → “Show me those transactions.” Use a category that exists but has no spending.
4. **Card list, fresh chat:** “What are the purchases on my Apple Card this month?”
5. **Topic changes, fresh chat:** “How much have I spent this month?” → “What is my planned-to-actual income progress?” → “Am I on track with my budget this month?”

Do not reset a chat between follow-ups within a scenario. If a turn fails, record it; do not assume a Retry succeeded because it finished generating. Verify the amount, scope, and visual independently. Stop if continuing is confusing; partial sequences are useful.

Paste one template for every turn:

```text
Scenario:
Fresh or existing chat:
Question asked: [optional; names may be anonymized]
Answer correct: Yes / No / Unsure
Visual appropriate: Yes / No / Unsure
Warning appeared: No / Before / During / After answer
Other observations:

[Complete MarinaTokens report]
```

## How to interpret measurements

Standalone instructions, schema, tool-set, prompt, and output counts overlap with transcript totals. **Do not add component counts to transcript counts.** Use initial/final transcript measurements to assess occupied context, and individual components to locate costs. Token counts reflect what Apple's API represents; they are not a guarantee of remaining usable generations.

Timing separates session preparation, the existing context preflight, stream start to first text, response completion, and post-response context checks. Additional diagnostic counting occurs after generation, outside the streaming loop. Total elapsed time is not labeled pure model-generation time.

A smaller measured tool set is an overhead experiment, not evidence that Marina can handle every question with those tools. Compare the **all five** initial-transcript row for production overhead. The implementation uses automatic renewal, prewarming, and availability-gated Dynamic Profiles; it does not introduce domain routing, a cloud model, or an external package.

## Engineering benchmark and local acceptance

The Debug test `MarinaToolSetBenchmarkTests.unchangedProductionToolCombinations` runs when `MARINA_SCHEMA_BENCHMARK=1`. It uses actual production tool definitions, identical production instructions, and synthetic context. It prints `MarinaBenchmark` rows for all five tools; lookup plus expenses, income, budget, or accounts; and lookup plus expenses plus income. Measurements are native, never character-count estimates. `measurement=unavailable` or an API-unavailable failure blocks the comparison.

Native conversation tests use `MARINA_MODEL_EVALUATION=1`, with `MARINA_TOKEN_DIAGNOSTICS=1` for reports. `MarinaPresentationLiveTests` includes repeated full spending sequences, workspace timing, category/empty results, income/budget/presets, named-record safety, and restored saved history. Fixtures retain their in-memory model containers and do not read the user's workspace. Disabled native tests are not behavioral passes.

Current-run measured counts and verification outcomes are reported in the implementation handoff. A functioning diagnostic package is separate from conversational acceptance; any native-model failures must be reported without changing financial behavior to hide them.

## Renewable conversations — October 23, 2026

The app uses the device-reported `contextSize` and reserves `max(1,024, ceil(capacity / 4))` tokens for tool work and narration. On iOS 26.4 and later it uses Apple's native token counter. Earlier iOS 26 releases use conservative, separately calibrated prefix and text estimates. The fallback is an estimate, not a measurement; the schema benchmark asserts that it covers the measured production prefix on the test device.

Before generation, Marina fits a bounded, deterministic memory and the newest complete visible exchanges into that input budget. It drops older exchanges first, then reduces memory by complete units. A genuine framework context-overflow error renews and retries once using the same visible answer ID. An oversized request gets a narrower-request response without locking the chat. Historical saved limit markers no longer disable the composer.

`MarinaConversationMemory` stores confirmed entity IDs/names, validated query scope and dates, comparisons, pending clarification candidates, paging state, and result references. It stores no balances or amounts. It is versioned and scoped to both workspace and chat through the existing `followUpContextData`; unknown legacy payloads remain inert and visible history remains readable. Validated relative periods are frozen to their actual dates. Instructions require fresh financial reads on follow-ups; native evaluation must still verify that the model obeys them. UI pagination also updates this memory before the next model request.

iOS 26 renews static sessions. iOS 27 uses a Dynamic Profile with a shared retention policy that preserves instructions, tools, and the entire active tool chain. The profile's model-facing transform does not delete saved chat messages. Sessions prewarm when the active chat opens and after renewal, and are released on navigation away. Instructions/tools remain stable between renewals.

Model-facing results contain operation-relevant facts and exact formatted currency. Account facts and transaction previews are bounded; full totals, clarification choices, scope, financial meaning, and pagination remain available. Saved financial presentations retain their complete results. No SwiftData schema migration, external model provider, new dependency, or financial-calculation change is included.

### Native acceptance procedure

Enable `MARINA_MODEL_EVALUATION=1` and `MARINA_LONG_MODEL_EVALUATION=1` to run `MarinaLongConversationTests` separately from other native-model suites. With `xcodebuild`, use the corresponding `TEST_RUNNER_` environment-variable prefixes. `MARINA_LONG_STATIC_SESSION=1` exercises the iOS 26 session implementation on a newer OS; it does **not** establish iOS 26 device performance. `MARINA_LONG_EVALUATION_VERBOSE=1` prints synthetic fixture requests and retained memory only from this opt-in test suite; never enable similar raw output for real workspace diagnostics.

The suite covers a 20-turn mixed-domain conversation with at least two renewals, a 4K-budget saved-chat restoration with data edited between turns, oversized-prompt recovery, cancellation, and rapid chat/workspace switching. A Debug-only injected-overflow case throws the real framework error type after a real financial tool result; it verifies one retry, stable answer identity, removal of failed-attempt visuals, and usability after a second overflow. This injection tests recovery logic, not actual device capacity. The suite verifies visible-history preservation, answer identity, fresh reads, exact fixture results, scope, ambiguity, and account pagination. Failures remain failures; completing 20 turns alone is insufficient.

Collect cold, warm, and post-renewal time to first text and total time separately, using the same physical device and workload on iOS 26 and iOS 27. A Mac Catalyst native-model run verifies the host's model behavior, not iPhone latency. No response-time improvement is promised by token reductions alone. Apple's Foundation Models instrument is still needed to separate loading, input processing, scheduling, and inference.

### Initial renewal verification, before the native accuracy fixes below

The final focused iOS 26.3 simulator run passed **94 tests across 13 suites**. Coverage includes schema decoding and operation mapping, compact facts and full saved results, memory/version/workspace boundaries, whole-turn retention, legacy limit markers, storage, financial-service parity, and diagnostics. The app and test targets compile for iOS 26.3 and Mac Catalyst 27.0.1.

Native token measurements on Mac Catalyst 27.0.1, using all five production tools and the same synthetic context as the October 17 benchmark:

| Measurement | October 17 | October 23 |
|---|---:|---:|
| Complete tool set | 4,554 | 2,364 |
| Initial transcript | 5,366 | 2,699 |
| Reported capacity | 8,192 | 8,192 |

Initial overhead fell **49.7%**, occupying about 33% of this device's capacity. The fallback prefix estimate is 2,851 tokens, above the native measurement. The below-half-capacity target is met on this 8K host, but **not established for 4K devices**: the same measured prefix would occupy about 66% of 4K. A 4K budget leaves only 373 measured tokens after the 1,024-token reserve, before the question and remembered context; more aggressive compaction on those devices is expected.

**Native conversational acceptance is not met.** The final Dynamic Profile run executed nine tests: six passed and three failed, with 29 recorded issues. The 20-turn test retained all 20 visible messages and performed seven renewals without requiring a new chat, but failed 21 accuracy/lifecycle expectations. Failures included dropping a resolved card filter, choosing the wrong account or topic, and looping on a merchant clarification until the tool-call cap. The two older live conversation tests also failed card-scoping and clarification checks. These results must not be described as a successful long-conversation accuracy evaluation.

The 4K-budget saved-chat restoration test passed, including a fresh read after the underlying data changed. Oversized-prompt recovery, cancellation/retry identity, chat/workspace switching, and injected one/two-overflow recovery all passed. The token benchmark also passed. The older live fixtures now retain their in-memory containers, so those two tests reach inference instead of crashing during fixture construction.

The final static-session compatibility run also retained all 20 visible messages and renewed three times, but failed 29 expectations involving card/category/account scope, clarification, comparisons, and completion state. Its 4K-budget saved-chat test failed one date-context expectation. This exercises the iOS 26 implementation on macOS 27.0.1, not an iOS 26 physical device. The same invocation re-ran three older presentation tests against the final production Dynamic Profile path: screenshot conversation, budget/income/presets, and workspace/named-target safety. They failed eight, two, and four expectations respectively. This invocation therefore ran five failing tests with 44 issues. An earlier investigation run was interrupted by an AppKit toolbar-constraint exception; that host exception is separate from model-accuracy failures and is not counted as a model pass.

For the final 20-turn Dynamic Profile run on Mac Catalyst, these are session-phase timings, not a cold-device benchmark:

| Session phase | Turns | Time to first text | Total turn time |
|---|---:|---:|---:|
| New session | 1 | 7.327 s | 7.523 s |
| Continuing session | 12 | 4.471–14.724 s | 6.366–15.556 s |
| After renewal | 7 | 5.716–11.094 s on six turns | 8.374–56.099 s |

The seventh post-renewal turn produced no text and failed at the tool-call cap after 56.099 seconds. In the static-session run, first text took 8.003 seconds for the initial turn, 4.808–18.730 seconds across 16 continuing turns, and 5.772–11.010 seconds across three post-renewal turns. Total times were respectively 8.209, 6.506–26.672, and 7.360–25.951 seconds. These workloads include financial tools and differ from the October 17 workspace-only timing case. There is no demonstrated latency improvement, and no physical iOS 26/iOS 27 or Instruments performance comparison was completed.

The physical iOS 27.0.1 iPhone build succeeded, but Xcode could not launch its native tests because the device was locked. Unlocking was requested; the still-pending launch was stopped before the handoff, and no device results are claimed. Both connected physical iOS devices reported 27.0.1, so a physical iOS 26 comparison also remains outstanding.

A bounded schema experiment restored the original expense-filter variants. It measured 3,036 initial tokens (3,265 estimated), leaving only 36 tokens before the 3,072-token input ceiling on a hypothetical 4K device. The experiment was fully reverted; it did not establish an accuracy improvement. Further work must address native target selection, clarification, and narration grounding without silently broadening queries or accepting fewer capabilities. Domain routing and extra model-classification passes remain deferred as requested.

Local, uncommitted test artifacts: `/private/tmp/marina-renewal-regression-verified.log`, `/private/tmp/marina-renewal-native-verified.log`, `/private/tmp/marina-renewal-static-verified.log`, `/private/tmp/marina-renewal-device-verified.log`, and `/private/tmp/marina-filter-native-benchmark.log`. Simulator passes and reduced token costs do not establish model accuracy or faster responses.

### Native accuracy follow-up — October 23, 2026

The follow-up replaces model-supplied database identifiers with validated, workspace/chat-bound references (`r1`, `r2`, etc.). A shared scalar selection represents workspace, previous, or explicit references. Previous selection and previous dates come from the latest validated financial query; name lookups cannot replace the financial period. References are bounded, survive renewal/restoration, and are never reassigned to a different entity. Unknown, expired, foreign, deleted, or incompatible targets cannot silently become an unfiltered read.

Named lookups preserve ambiguity unless the current question explicitly supplies a record kind. Card/merchant and savings/reconciliation names remain distinct. The bridge validates literal targets against a fresh, workspace-scoped name catalog even when the model skips lookup. An old reference cannot satisfy a newly ambiguous name. Kind words must attach to the target: “on my card at Apple” does not resolve Apple to a card. Quoted/named unknown records and title-case card names are checked conservatively; arbitrary unquoted unknown names are not a complete supported grammar. Generic financial nouns and invented protocol labels cannot become false missing-name answers, while explicitly named records remain searchable. Conservative constraints honor explicit universal scopes while retaining unrelated filters; comparisons, exclusions, and mixed scopes are left to typed request validation. The data service also checks an account ID against the requested account domain. Financial calculations and saved financial records are unchanged.

Clarifications display verified candidate names and kinds and stop inference while the person chooses. A restored clarification still requires an affirmative candidate choice; a generic acknowledgment does not authorize the model to select one. Supported explicit calendar cues freeze the unresolved question's period through the existing date resolver. That period survives restoration and an interrupted candidate lookup, until a financial read completes or an explicit new topic replaces it. Explicit new dates override the pending period. Unsupported or multiple date cues do not trigger automatic date inference.

Financial captions use the validated result's amounts, dates, qualifications, and reconciliation direction. They can appear as soon as a read completes. A conservative English/Spanish evidence policy suppresses unsupported prose for recognized financial requests; it is not a complete natural-language intent parser. On iOS 27, a session property requires tool calls until a financial read succeeds, then allows narration; verified ambiguity or a missing name ends generation with a question. This follows [Apple's required-tool guidance](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling), including its required exit condition. On iOS 26, a missing read for those requests triggers one bounded renewal/retry and otherwise produces a safe verification failure. Greetings, workspace metadata, general definitions, and creation forms retain their ordinary paths. All five tools remain available without a separate model-classification pass or new provider.

Comparison arguments use `operation: "compare"`/`"compareIncome"` and a sibling `comparison` payload containing the other selection and its dates. Validation requires that payload exactly when comparing. A recognized request to compare two calendar periods cannot be satisfied by two independent transaction lists. Planned/received income and unambiguous follow-up selections are validated independently of older card topics. Generic account follow-ups preserve the previous savings/reconciliation domain as well as the selection. Selected accounts display their full balance alongside paged ledger activity; an account list retains all balances and supports paging. These are request and presentation changes, not new financial calculations.

For requests requiring financial evidence, lookup names must occur affirmatively in the current question, the pending question being answered, or the latest financial selection during a contextual follow-up. Arbitrary names from an older inventory cannot authorize a lookup. A malformed argument decoded before the tool body can use the same single missing-read renewal/retry; it does not gain another independent retry. A first, closed-vocabulary unnamed expense/income total can explicitly repair a model-invented unknown reference to workspace. That exception requires no financial history, pending/resolved name, unresolved lookup, or current named requirement, and excludes known foreign/stale/wrong-kind reference failures. Named targets cannot use it to broaden a read.

`MarinaLongEvaluation.first_visible_text_s` now measures the first displayed caption or narration. It is not interchangeable with the older model-narration-only timing. `MarinaTokens.stream_to_first_text_seconds` still measures the first model-generated text snapshot. Native accuracy, visible response latency, and total completion time must be assessed separately.

### Usage-limited checkpoint — October 23, 2026

Work stopped at the user's requested usage checkpoint. The final Mac Catalyst build and **222 focused tests across 19 suites passed** (`/private/tmp/marina-accuracy-checkpoint.log`). The final native token benchmark measured 2,350 tokens for all five tools and **2,676 initial transcript tokens**, versus the October 17 initial baseline of 5,366. The host reports 8,192 capacity; the fallback prefix estimate is 2,850 with 9,259 schema bytes. This is about a 50% startup reduction and below half this host's capacity, but not below half a hypothetical 4K capacity.

The last native sweep (`/private/tmp/marina-accuracy-long-v9.log`) completed the 20-turn script with all visible answers retained, seven session renewals, and **six capacity-driven renewals**. No turn forced a new chat. **Native accuracy acceptance still failed:** comparison sides were reversed, an income-progress follow-up became a card-filtered period comparison, and a named-budget pace question produced an overview. A newly strengthened activity assertion also checked the wrong representation; it now checks the exact saved answer row, dates, and transaction amounts. The separate restored-clarification sequence encountered an account-validation loop when Alex existed in both account domains. The short card/date/comparison sequence passed.

The last edits correct those explicit operation/date constraints and recognize single-target account-domain wording such as “reconciliation balance with Alex.” They have deterministic regression coverage but **have not been rerun through the native model**. The earlier upcoming-preset and income-percentage corrections also await native revalidation. Do not interpret passing unit tests as a native accuracy pass or expand phrase-specific rules without a bounded evaluation decision.

Observed times in that 20-turn run, including its inaccurate answers:

| Session phase | Turns | First visible text | Total completion |
|---|---:|---:|---:|
| Cold | 1 | 24.854 s | 26.083 s |
| Warm | 12 | 6.998–25.163 s | 9.746–31.001 s |
| After renewal | 7 | 5.936–17.398 s | 8.216–17.398 s |

The sweep was intentionally interrupted during the following saved-chat test to conserve usage. Remaining native recovery cases and the static-session 20-turn run were not rerun on the final source. Physical iOS 26/iOS 27 testing remains deferred at the user's request. No latency improvement or completed native acceptance is claimed. A future bounded check should first rerun the failed cases, then assess whether broader model-routing work is warranted instead of continuing open-ended semantic patches.

### Files and review phases

1. Tool cost: `MarinaTools.swift`, `MarinaDataResult.swift`, and the resolved-query metadata in `MarinaReadOnlyDataService.swift`; schema/fact and benchmark tests.
2. Context lifecycle: new `MarinaConversationMemory.swift`, `MarinaContextBudget.swift`, and `MarinaTranscriptWindow.swift`; runtime, controller, store, panel, context/response status, and diagnostics; memory/history/storage/retention tests.
3. Accuracy validation: new `MarinaTurnPolicy.swift`, `MarinaNamedTargetRequirement.swift`, `MarinaGroundingPolicy.swift`, `MarinaVerifiedNarration.swift`, `MarinaClarificationRequired.swift`, and the availability-gated `MarinaSessionProfile.swift`; tool bridge integration and focused regressions.
4. Native verification: `MarinaLongConversationTests.swift`, the retained in-memory containers in native/presentation tests, and this testing guide. No financial math or SwiftData schema change is included.

## Measured baseline — October 17, 2026

Native Apple token counting on macOS 27.0.1, Mac Catalyst, with fixed synthetic workspace/date and the restored production instructions:

| Tool configuration | Complete tool set | Initial transcript | Startup reduction vs. baseline |
|---|---:|---:|---:|
| All five (production) | 4,554 | 5,366 | 0 |
| Lookup + expenses | 1,939 | 2,751 | 2,615 |
| Lookup + income | 1,593 | 2,405 | 2,961 |
| Lookup + budget | 1,238 | 2,050 | 3,316 |
| Lookup + accounts | 951 | 1,763 | 3,603 |
| Lookup + expenses + income | 3,143 | 3,955 | 1,411 |

| Tool | Argument schema | Complete definition |
|---|---:|---:|
| findRecords | 303 | 389 |
| readExpenses | 1,549 | 1,596 |
| readIncome | 1,219 | 1,250 |
| readBudgetSummary | 892 | 895 |
| readAccounts | 596 | 608 |

Individual definitions share schema content; their sum is not the combined-set measurement. Real workspace names, locale and Home period can change startup counts. These are overhead-only subset measurements with identical unchanged instructions; no reduced-set conversation or dynamic-profile implementation was tested or enabled.

### Implementation and verification notes

Changed areas: the new `MarinaTokenDiagnostics` collector; observation hooks in the existing runtime, controller and tool bridge; the main Run scheme; focused diagnostic/parity tests; native benchmark and conversation tests; this guide and its narrow `.gitignore` exception. No model schemas, instructions, financial calculations, saved-data formats, or UI layouts were changed.

All 21 generated definitions, the tool description literals, and the production instruction text were compared with the restored Git baseline and are unchanged. The focused simulator run passed 44 tests across nine suites. The six diagnostic/parity tests also passed after final instrumentation updates. The tests compare exact returned strings and requests; saved-answer comparisons exclude only independently generated display UUIDs and creation time, while preserving entity IDs, scope, values, pagination and presentation identity keys.

Reports distinguish tool entry, mapped requests, service-execution checkpoints, and returned outputs. A clarification response can return without entering the data service. These are application-level checkpoints, not a count of underlying SQL statements. Entered-argument counts use re-encoded generated content; transcript argument counts use the framework's recorded serialization and can differ. Neither should be added to transcript totals.

Additional report counting happens asynchronously after the response. Wait for `END REPORT` before copying. For engineering timing comparisons, finish the preceding report before submitting the next turn, and avoid running the schema benchmark alongside the conversation being timed. The first conversation in this local run overlapped the independent schema benchmark, so its latency is not an isolated startup benchmark.

### Native conversation findings

- All three repetitions of monthly spending → Apple Card amount → transactions → largest purchase passed. One of two first-question paraphrases also passed the complete sequence: **four of five sequences passed**.
- The other paraphrase retained the correct card scope through the list, then made an exact repeated largest-purchase request and failed during generation. The report recorded `same_request_as_call=1`. The final transcript API count remained 7,226, below the reported 8,192 capacity; this trace alone does not establish a context-limit error.
- The older screenshot test using “Apple Card card” failed card scoping and subsequent list/largest assertions; a later category turn failed generation.
- Fresh category ranking and empty Hair Care queries passed.
- Shared budget/income/upcoming-preset checks exposed wrong analytical-purpose selections and upcoming-period selections. Income progress passed in the topic-change sequence but a separate paraphrase did not select the expected purpose.

These are measured behaviors of the unchanged all-tools baseline, not evidence that diagnostics or reduced tool sets corrected conversational behavior. No reduced tool set was used for these conversations.

- Workspace questions made no tool calls. Unknown and ambiguous names, a card belonging to another workspace, and the restored-history card follow-up all passed their native checks.
- The complete native run executed seven tests: three passed and four failed, with 15 assertions/issues reported. The repeated-sequence test is one aggregate test; four of its five full conversations passed as described above. No failed native case was changed or hidden in this diagnostic pass.

Workspace timing (same local run; not a cold-device benchmark):

| Measurement | Fresh session | Continuing session |
|---|---:|---:|
| Session preparation | 0.002 s | <0.001 s |
| Existing context preflight | 0.073 s | 0.072 s |
| Stream start to first text | 6.764 s | 6.798 s |
| Stream completion | 6.802 s | 6.833 s |
| Existing context postflight | 0.052 s | 0.049 s |
| Tool calls | 0 | 0 |
| Initial → final transcript | 5,365 → 5,389 | 5,389 → 5,415 |

The delay in these two turns was overwhelmingly inside the streaming request before visible text, not database execution or the context check. This does not identify the framework's internal cause; an Instruments trace would be needed to separate model loading, prompt processing, scheduling, and inference.

Local logs are build artifacts under `/private/tmp`: `marina-baseline-native.log`, `marina-baseline-simulator-final.log`, `marina-baseline-final-check.log`, and `marina-baseline-catalyst-final.log`. They are not committed. Simulator/CloudKit startup noise is separate from `MarinaTokens` reports; filter using that exact prefix when copying real-workspace results.

Final iOS Simulator and Mac Catalyst builds passed. An earlier simulator run exposed the now-corrected display-UUID assertion in the new parity test; the subsequent 44-test run and final six-test diagnostic rerun completed successfully.
