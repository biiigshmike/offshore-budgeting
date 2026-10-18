# Marina baseline diagnostics and manual testing

This pass measures the restored on-device implementation. It does not change prompts, tool definitions, financial calculations, presentation selection, or the 75% context warning. All five production tools remain available. Reports use **format 4**.

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

A smaller measured tool set is an overhead experiment—not evidence that Marina can handle every question with those tools. The production implementation still supplies all five tools. No routing, dynamic profiles, cloud model, prewarming, or automatic context renewal is introduced.

## Engineering benchmark and local acceptance

The Debug test `MarinaToolSetBenchmarkTests.unchangedProductionToolCombinations` runs when `MARINA_SCHEMA_BENCHMARK=1`. It uses actual production tool definitions, identical production instructions, and synthetic context. It prints `MarinaBenchmark` rows for all five tools; lookup plus expenses, income, budget, or accounts; and lookup plus expenses plus income. Measurements are native, never character-count estimates. `measurement=unavailable` or an API-unavailable failure blocks the comparison.

Native conversation tests use `MARINA_MODEL_EVALUATION=1`, with `MARINA_TOKEN_DIAGNOSTICS=1` for reports. `MarinaPresentationLiveTests` includes repeated full spending sequences, workspace timing, category/empty results, income/budget/presets, named-record safety, and restored saved history. Fixtures retain their in-memory model containers and do not read the user's workspace. Disabled native tests are not behavioral passes.

Current-run measured counts and verification outcomes are reported in the implementation handoff. A functioning diagnostic package is separate from conversational acceptance; any native-model failures must be reported without changing financial behavior to hide them.

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
