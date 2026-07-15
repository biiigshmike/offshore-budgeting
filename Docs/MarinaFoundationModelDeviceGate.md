# Marina Foundation Model Physical-Device Gates

These serial plans exercise Marina's production `MarinaBrain.answerSeed` path with the real on-device Foundation Model. They are intentionally separate from the ordinary `OffshoreBudgeting` test plan. Simulator, Mac Catalyst, model unavailability, unsupported locales, missing source metadata, and preflight errors fail with a partial JSON/text report attached to the `.xcresult`.

## Prerequisites

- A physical iPhone or iPad running iOS/iPadOS 26 or newer.
- Apple Intelligence enabled and `SystemLanguageModel.default.availability == .available`.
- All six shipped non-English locales supported by the installed system model.
- The device unlocked and connected to Xcode.
- A unique result-bundle path for each run.

Capture source identity before running any plan:

```bash
SOURCE_REVISION=$(git rev-parse HEAD)
if [[ -n $(git status --porcelain) ]]; then SOURCE_DIRTY=true; else SOURCE_DIRTY=false; fi
```

The plans propagate these values into the test process. Omitting them fails preflight so an untraceable artifact cannot satisfy a release gate.

## 1. Calibration — 20/20 required

This runs the two observed QA failures ten times each. Every invocation must match on its first model attempt.

```bash
xcodebuild test \
  -scheme MarinaFoundationModelDevice \
  -testPlan MarinaFoundationModelDeviceCalibration \
  -destination 'platform=iOS,id=<DEVICE_UDID>' \
  -resultBundlePath '<ARTIFACT_DIR>/MarinaFoundationModelDeviceCalibration.xcresult' \
  MARINA_SOURCE_REVISION="$SOURCE_REVISION" \
  MARINA_SOURCE_DIRTY="$SOURCE_DIRTY"
```

## 2. Blocking matrix — 48/48 required

This runs the eight production English starters, two QA regressions, and six localized safe-spend prompts three times each.

```bash
xcodebuild test \
  -scheme MarinaFoundationModelDevice \
  -testPlan MarinaFoundationModelDeviceBlocking \
  -destination 'platform=iOS,id=<DEVICE_UDID>' \
  -resultBundlePath '<ARTIFACT_DIR>/MarinaFoundationModelDeviceBlocking.xcresult' \
  MARINA_SOURCE_REVISION="$SOURCE_REVISION" \
  MARINA_SOURCE_DIRTY="$SOURCE_DIRTY"
```

All 48 invocations must use the Foundation Model, compile on the first attempt, pass alignment and semantic validation, execute through the universal path, and leave the fixture unchanged. A test-only interpreter executes the exact expected semantic request against an isolated copy of the seeded active Workspace. The real-model answer and evidence must exactly match those deterministic SHA-256 signatures. The real-model fixture also contains a high-value sentinel Workspace, so numeric contamination fails even when no sentinel name is presented. Any direct sentinel exposure also fails the gate.

## 3. Full release-corpus soak — 272 cases

Selecting this plan is the explicit opt-in; no environment toggle is required.

```bash
xcodebuild test \
  -scheme MarinaFoundationModelDevice \
  -testPlan MarinaFoundationModelDeviceCorpusSoak \
  -destination 'platform=iOS,id=<DEVICE_UDID>' \
  -resultBundlePath '<ARTIFACT_DIR>/MarinaFoundationModelDeviceCorpusSoak.xcresult' \
  MARINA_SOURCE_REVISION="$SOURCE_REVISION" \
  MARINA_SOURCE_DIRTY="$SOURCE_DIRTY"
```

Semantic accuracy is reported by corpus group and locale and remains nonblocking. Every turn records its own typed compiler attempts, semantic outcome, execution result, answer/evidence signatures, duration, write check, and sentinel check. Any write-side effect or Workspace-boundary violation on any turn is blocking.

## Artifact and release policy

Each `.xcresult` retains V4 JSON and text reports with test mode, expected/actual redacted semantics, per-attempt diagnostics, V3.1 `outcomeRoute/financialDomain/actionRoute/actionPayload` paths, per-phase and total duration, execution/answer/evidence outcomes, device/OS/app build, model availability, generation settings, catalog/corpus versions, source revision, and dirty state. Reports contain SHA-256 answer/evidence signatures and value-free semantic digests rather than prompts, fixture values, names, IDs, amounts, or raw generated payloads.

Required order:

1. Focused deterministic tests.
2. Full ordinary test suite.
3. Calibration plan with 20/20 passing.
4. Blocking plan with 48/48 passing.
5. Corpus soak artifact review.

Until the blocking `.xcresult` passes, report the repair as `code-complete, device-validation-blocked`; do not call it safe or ready for manual QA. Manual QA must use the exact gated app build and a fresh conversation per prompt. On the first mismatch, stop, retain the complete QA Trace plus device/OS/app/compiler versions, and reopen the device gate before testing further.
