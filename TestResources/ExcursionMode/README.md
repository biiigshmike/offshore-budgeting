# Excursion Mode location replay

These public-area simulation fixtures exercise South Bay Village shopping center in Torrance, California. They contain no home coordinate and no McDonald’s override.

## Run the complete Excursion UI suite

Select the **ExcursionMode** test plan in the OffshoreBudgeting scheme. It explicitly includes all four Excursion UI test classes and disables parallel execution. The permission and GPS tests share system-level simulator state, so run serially on a dedicated simulator. The full iPhone run includes diagnostic access before/after location permission setup, the five-stop route, location permission/expiry, existing reminder choices, preferences, and notification suggestion navigation; allow approximately 25 minutes.

```bash
xcodebuild test -project OffshoreBudgeting.xcodeproj \
  -scheme OffshoreBudgeting -testPlan ExcursionMode \
  -destination 'platform=iOS Simulator,id=YOUR_DEDICATED_IPHONE_UUID' \
  -parallel-testing-enabled NO \
  -resultBundlePath /tmp/ExcursionSuite.xcresult \
  CODE_SIGNING_ALLOWED=NO > /tmp/ExcursionSuite.log 2>&1
```

The two sidebar tests intentionally skip on iPhone. Run `ExcursionPreferencesUITests/testSidebarDefaultRendering` and `ExcursionPreferencesUITests/testSidebarIgnoresLegacyThemePreference` on an iPad destination to cover them.

Navigation helpers wait for Settings and each destination navigation bar before looking for controls, then scroll the settings list rather than the whole application. Notification consent supports both an empty setup and existing reminder selections, verifies the authorized state, and turns scheduled reminders off afterward. DEBUG `-uiTestingReset` clears the shared Excursion session, legacy session values, cooldowns, and pending widget route in addition to ordinary test preferences. Relaunches without that reset flag continue to test preference persistence. No production financial data or detection policy is changed by these test-isolation fixes.

### Full-suite verification after navigation/setup fixes (November 7, 2026)

- **Full ExcursionMode plan, iPhone 17e / iOS 27.2:** 16 selected tests, **14 passed, 2 platform skips, 0 failures**, 1481.786 seconds (24 minutes 42 seconds). This was one serial invocation with no per-test exclusions; the five-stop route, all three location/setup tests, preferences, and all five suggestion routes ran together.
- **iPad mini (A17 Pro) / iOS 27.2:** both sidebar tests passed together, **2 passed, 0 failures**, 40.666 seconds. These are the same two tests intentionally skipped on iPhone. All 16 unique Excursion UI cases passed on an applicable platform.
- The full iPhone run reused the simulator from an earlier shorter suite run (12 passed, 2 platform skips, 0 failures), rather than relying on another clean simulator. The new existing-reminder-choices case explicitly exercised notification setup with preselected reminders and no Set Up Reminders button.
- Full-suite result: `/tmp/offshore-excursion-suite-all.xcresult`; iPad results: `/tmp/offshore-excursion-sidebar.xcresult`; earlier shorter run: `/tmp/offshore-excursion-suite-fast.xcresult`. Logs use the same paths with `.log` instead of `.xcresult`. These local artifacts are not checked into the repository.
- This verification supersedes the earlier isolated-route claim for UI-suite coverage. It does not verify live MapKit results, physical-device background delivery, or unrelated UI suites. Unit/business-logic suites were not rerun for these test-navigation/reset-only changes.

### Diagnostic access regression

A subsequent user run on iPhone 18 Pro / iOS 27.2 passed 13 tests and skipped two, but the five-stop test failed before starting its GPS route: the Excursion screen and Active status were visible while the separate bottom-inset diagnostic label was absent. That result does not establish a GPS/notification failure. The exact reason the inset was absent was not established from the saved evidence.

Diagnostic JSON now uses the accessibility value of the existing `excursionStatus` text instead of an extra inset. The visible status label is unchanged. The snapshot reports `fixtureEnabled`, so absent instrumentation and a missing fixture flag produce distinct failures. Diagnostic reads have a bounded wait, attach the screen/hierarchy on failure, and report the caller's source line. `testDiagnosticsSurviveLocationPermissionSetup` checks this access before and after location authorization and after switching away from and back to Settings. These changes are DEBUG/UI-test only.

### Status-based diagnostic verification (November 7, 2026)

- Used the user's actual **iPhone 18 Pro simulator** (`25604EC2-E879-46EB-8F79-70662E8A02D2`), iOS 27.2, with normal Xcode signing (no `CODE_SIGNING_ALLOWED=NO` override).
- The new diagnostic preflight passed independently in 68.310 seconds and again as part of the full plan.
- Full **ExcursionMode** plan: **17 selected, 15 passed, 2 iPad-only skips, 0 failures**, 1567.774 seconds (26 minutes 8 seconds). The full six-notification route passed in 1117.797 seconds (18 minutes 38 seconds). All permission/setup, preference, and suggestion-routing tests passed afterward on the same simulator.
- Both sidebar tests passed on iPad mini (A17 Pro) / iOS 27.2 with normal signing: **2 passed, 0 failures**, 39.700 seconds. All 17 unique UI cases were verified on an applicable platform.
- Results: `/tmp/offshore-status-diagnostics-preflight.xcresult`, `/tmp/offshore-status-diagnostics-full.xcresult`, `/tmp/offshore-status-diagnostics-sidebar.xcresult`. Logs use the corresponding `.log` paths.
- This change affects DEBUG test instrumentation and test diagnostics only; physical-device/background and live MapKit checks remain separate. Business-logic suites were not rerun for the diagnostic-surface change.

### Suggestion launch ordering investigation (November 7, 2026)

The user's later `testChoosingMerchantOpensEditableQuickAdd` failure occurred before merchant selection: the saved accessibility hierarchy showed Home rather than Nearby Places. It does not establish a GPS, scheduling, or expense-form failure. The original failure did not include navigation traces, and the unchanged test passed ten consecutive serial repetitions on the same iPhone 18 Pro / iOS 27.2 simulator (`/tmp/offshore-chooser-repeat-baseline.xcresult`).

`AppRootView` now leaves pending section/segment requests intact until initial selection has run. This closes an ordering gap where an observer could consume the launch section before `onAppear` resolved it, allowing a fallback to Home. This is a targeted safeguard consistent with the observed screen, not a conclusively reproduced cause. Suggestion UI tests enable existing navigation traces and retain a screenshot and hierarchy on failure; they still require automatic chooser presentation without tapping Accounts or retrying the launch.

All five suggestion UI tests passed three repetitions each after the guard: **15 executions, zero failures**, `/tmp/offshore-chooser-startup-fix.xcresult`. Command: `xcodebuild test -project OffshoreBudgeting.xcodeproj -scheme OffshoreBudgeting -testPlan ExcursionMode -destination 'platform=iOS Simulator,id=25604EC2-E879-46EB-8F79-70662E8A02D2' -parallel-testing-enabled NO -only-testing:OffshoreBudgetingUITests/ExcursionSuggestionUITests -test-iterations 3`. This focused rerun does not repeat the full GPS route or establish physical-device background reliability. No financial models or detection policies changed.

Final-file validation also passed all five suggestion UI tests and all four `AppRootLaunchSectionResolverTests` with normal signing on the same simulator: `/tmp/offshore-chooser-final-validation.xcresult`. The full Excursion suite was not rerun for this focused follow-up; its earlier full-run results are recorded above.

## Automated five-stop UI regression

`ExcursionFiveStopUITests/testFiveStopsClusterAndReturnProduceSixVisibleNotifications` drives **A → B → C → D → E → A** using `XCUIDevice.shared.location`. Only merchant discovery is replaced under DEBUG when both `-uiTesting` and `-uiTestExcursionFiveStops` are present. Core Location callbacks, the 45-second default dwell, production cooldowns, local notifications, and notification-tap routing remain real. No expense is saved.

The synthetic stops use longitude **-118.3528396** and these latitudes:

| Stop | Latitude | Fixture businesses |
| --- | --- | --- |
| A | 33.8550064 | Route A |
| B | 33.8600064 | Route B |
| C | 33.8650064 | Route C1, Route C2, Route C3 |
| D | 33.8700064 | Route D |
| E | 33.8750064 | Route E |

All merchant radii are 100 meters. C's three businesses intentionally share a coordinate to make ambiguity deterministic; they are synthetic names, not claims about real businesses at these coordinates. Departure points are 0.0025 degrees south of the next stop. These are simulation jumps, not a navigable route or a driving-speed test.

The test supplies fresh locations approximately every 10 seconds, alternating sub-meter longitude offsets because assigning an identical coordinate repeatedly did not sustain callbacks on the tested simulator. It waits at least 130 seconds after each observed notification before the next arrival, checks no notification during the first 35 seconds of each arrival and rejects any observed banner before 45 seconds, and allows up to 100 seconds from arrival for a visible banner. At C it checks the three actual candidate IDs, taps the generic notification, verifies the three-business chooser plus Other, edits a description, cancels, and moves approximately 60 meters within the cluster for 135 seconds without another reminder. At least eight fresh callbacks must arrive during that suppression window; this exceeds the post-delivery 50-meter movement filter while staying inside all three 100-meter merchant radii. Returning to A must be more than eight minutes after its first reminder. Six unique scheduled IDs must match six foreground delivery IDs; each also requires a separately observed, hittable SpringBoard banner and successful tap navigation.

Use a dedicated iPhone simulator, foreground/While Using permission, Precise Location, and normal banner-enabled notification settings. Run serially; allow approximately 16–20 minutes. The test resets the app's UI-test workspace, stops any leftover Excursion session, and cancels all forms. Do not target a simulator containing data you want to preserve.

```bash
xcodebuild test -project OffshoreBudgeting.xcodeproj \
  -scheme OffshoreBudgeting \
  -destination 'platform=iOS Simulator,id=YOUR_DEDICATED_SIMULATOR_UUID' \
  -parallel-testing-enabled NO \
  -only-testing:OffshoreBudgetingUITests/ExcursionFiveStopUITests \
  -resultBundlePath /tmp/ExcursionFiveStops.xcresult \
  CODE_SIGNING_ALLOWED=NO > /tmp/ExcursionFiveStops.log 2>&1
```

Results attach screenshots and read-only JSON diagnostics containing received fixes, candidate IDs, session/workspace IDs (asserted stable across the route), scheduled IDs, and foreground delivery callback IDs. Assertions distinguish location delivery, detection/scheduling, delivery callbacks, banner presentation, and navigation. A callback or scheduled request alone cannot pass the test. DEBUG diagnostics are exposed as the accessibility value of the existing `excursionStatus` text during UI-test launches; the snapshot explicitly reports whether the five-stop fixture flag is enabled. The status label stays unchanged. Release builds omit the fixture and instrumentation.

This regression does **not** validate live MapKit results, GPS hardware accuracy, background suspension/wakeup, or locked-device delivery. Existing deterministic tests cover cooldown rejection, drive-bys, poor/stale fixes, interrupted dwell, and permission invalidation. Keep live MapKit and physical-device checks separate.

**Fixture availability:** this checkout contains the README but not the historical GPX files described below. The automated route above does not depend on GPX. The older replay instructions are retained as background, not as evidence that those files are available or that a live replay passed.

## Five-stop verification (November 7, 2026)

- Xcode 27.2, dedicated **Offshore Excursion Verification** iPhone simulator (iOS 26.3 runtime), foreground/While Using permission.
- Full UI route passed: **1 test, 0 failures, 1058.097 seconds (17 minutes 38 seconds)**. Six visible banners and six unique scheduled/delivered IDs; all suggestions retained one session and workspace.
- C contained exactly `route-C1`, `route-C2`, and `route-C3`. The 135-second cluster observation added **13 fresh callbacks** with the delivery count unchanged at three. Final route evidence recorded 72 processed fixes and six deliveries.
- Focused logic verification passed: **80 tests across five suites** (`ExcursionDwellTrackerTests`, `ExcursionLocationServiceTests`, `ExcursionModeReliabilityTests`, `ExcursionSuggestionTests`, `LocalNotificationServiceTests`). Use the `OffshoreBudgeting-UnitTests` scheme: the initial main-scheme unit run crashed in CloudKit onboarding before tests started; the isolated unit host passed.
- Initial UI attempts exposed test-harness issues: identical-coordinate assignments stopped producing fresh callbacks, and notification routing changed tabs after cancellation. Sub-meter sample jitter and navigation back to Excursion settings resolved those issues without changing production detection. A superseded intermediate run was stopped to strengthen cluster callback assertions.
- Passing local evidence: `/tmp/offshore-excursion-five-ui-v4.xcresult`; exported screenshots and JSON traces: `/tmp/offshore-excursion-five-passed/`; focused logic results: `/tmp/offshore-excursion-five-focused.xcresult`. These are local run artifacts, not checked-in fixtures.
- App/widget/test targets compiled for Simulator. Full unrelated suites, live MapKit replay, Catalyst/Release builds, and physical-device background/locked-phone checks were not run for this change. Simulator success is scoped to the foreground route above.

## Coordinate provenance

Anchor: **33.8550064, -118.3528396**, the public charging location at **19330 Hawthorne Boulevard**, South Bay Village. Verified against the [Open Charge Map record](https://openchargemap.org/poi/details/158586), which attributes its coordinate data to NREL/US Department of Energy station 151261. The shopping center address is independently corroborated in the [Los Angeles City Clerk’s published retail-center inventory](https://cityclerk.lacity.org/onlinedocs/2014/14-1647_misc_f_12-3-14.pdf). Sources checked November 5, 2026. The charging record is not recently field-verified; this is a public simulation anchor, not a claim about an exact storefront entrance or current charger operation.

The supplied [Apple Maps short link](https://maps.apple/p/Rd5BdCH07L3FxX) could not be resolved by the research environment. Other waypoints are deliberately constructed offsets near the verified public anchor, not surveyed walking/driving routes. Do not use these files as real-world navigation directions. MapKit merchant results can change; verify the visible POIs before evaluating a named-merchant result.

## Replay in Xcode

1. Run the main app on an iPhone Simulator or a development iPhone. Grant notifications, Precise Location, and the desired location authorization. Select a workspace with an available card.
2. Add the desired GPX to the Xcode project navigator as a reference without app target membership, or select it as a scheme’s simulated location. Enable **Allow Location Simulation** in the Run scheme options. Use Xcode’s **Debug → Simulate Location** selection while attached.
3. Enable Excursion Mode and replay at real elapsed time. The default dwell is **45 seconds**, with no more than **22.5 seconds** between qualifying samples. The 60- and 120-second options allow gaps of 30 and 60 seconds respectively. Accelerating through coordinates does not establish dwell. Check actual callback timestamps/accuracy in the debug console. GPX replay behavior depends on Xcode; repeated stationary waypoints must actually generate fresh callbacks to count.
4. Verify candidate/suppression diagnostics and notification content. Tap a reminder, choose a merchant or Other, and verify editable Quick Add. Cancel to avoid adding test financial history.
5. Disable simulation after the test. Restart Excursion Mode between independent scenarios to reset session cooldowns.

Apple documents [GPX replay and XCUILocation UI-test simulation](https://developer.apple.com/documentation/xcode/simulating-location-in-tests). Deterministic unit tests inject fix timestamps, accuracy, speed, and merchants separately; GPX is for the system integration path, not an assertion that every device will deliver a notification at an exact second.

| Fixture | Intended observation |
| --- | --- |
| InitialDwell | Starting in the area is eligible after 45 seconds of qualifying samples by default; no immediate startup purchase claim. |
| ApproachDwellDeparture | Approach, hold for 150 seconds, then depart. At most one notification for that stop. |
| AdjacentStops | Move about 117 meters between two dwell locations. Overlapping merchant radii can remain one stop; no duplicate reminder merely because ranking changes. |
| DriveBy | Roughly 14 m/s movement through the area. No dwell reminder. |

## Category selection

The default selects Food & Drink, Shopping, Groceries, and Fuel & Charging. Select All selects every supported Apple category. The separate Include uncategorized places toggle permits results without a recognized category; known categories still need to be selected. Existing All Places preferences migrate to every category selected with this toggle enabled. The resolver sends the filter to both broad POI and supplementary text requests, then validates the actual `MKMapItem.pointOfInterestCategory` before deduplication and the nearest-20 limit. Search terms and app display hints never substitute for Apple metadata.

For a live check, select a narrow category such as Gas Station in Categories, replay a dwell, and confirm the eligible candidate list contains only that category. Repeat with Select All and Include uncategorized places enabled. Merchant availability and classification depend on MapKit, so an omitted or unclassified business may not appear while Include uncategorized places is off. All fixtures now have waypoint gaps of at most 15 seconds, including approach, adjacent movement, and departure segments. Added points linearly interpolate the existing path while preserving original waypoints, total duration, and each segment’s intended speed. XML/timestamp validation confirms the cadence is suitable for the default 22.5-second gap if the simulator emits fresh callbacks as expected.

## Deterministic regression coverage

`ExcursionDwellTrackerTests` covers initial dwell, stale/repeated fixes, missing/poor fixes, driving, departure/reentry, dense candidates, and empty discovery. `ExcursionModeReliabilityTests` covers the 300-foot versus 0.2-mile ordering, stale geofence state, radius eligibility, A → B → A cooldown, broad discovery, deduplication, nearest-20 capacity, category filtering before limits/deduplication, metadata-only classification, unknown categories, and backward-compatible cached merchant decoding. `ExcursionLocationServiceTests` replays those samples through the service, including callback order, failed/in-flight delivery, permission/session invalidation, workspace preservation, coarse discovery fixes, bounded sampling, and restored delivered-stop suppression. Live MapKit checks intentionally have no fixed merchant-name assertions.

## Short physical-device check

Simulator success does not validate suspended-app delivery. On a development iPhone with Always + Precise Location, start Excursion Mode near a public shopping area, lock the phone, remain nearby for at least three minutes, and inspect the notification and debug evidence after unlocking. Repeat with session expiry during confirmation; no reminder should be scheduled after expiry. Test While Using separately: backgrounding must pause detection. Test Precise Location off: show unavailable guidance without claiming background readiness. Confirm normal Focus/notification settings remain respected.

Record device/iOS version, authorization, start/expiry times, actual fix ages/accuracy, selected candidates, and scheduling result. Do not record a private starting address. These manual checks require an attached device or a person at the location and are not implied to have run by the presence of these fixtures.

## Preferences verification (November 5, 2026)

- Focused preference/discovery/dwell/location/suggestion tests: 71 tests, 79 parameterized executions, zero failures.
- Active-session coverage includes changes during discovery, dwell, and scheduling; delivered-stop suppression, departure through an area with no matching POIs, and session/workspace preservation.
- All three preference UI flows passed after correcting navigation/search presentation and the test’s search-dismissal handling. Five existing merchant-chooser UI regressions also passed.
- iOS app/widget and Mac Catalyst builds passed with signing disabled.
- For a fresh on-device comparison after a reminder has already fired at your current stop, stop and restart Excursion Mode. Changing preferences intentionally preserves that stop's duplicate suppression.

## First-wave baseline verification (November 5, 2026)

- Baseline before category/timing preferences: focused iOS Simulator regression run: 65 tests, 73 executions including parameterized cases, zero failures. Covers dwell, location lifecycle, ranking/discovery, suggestion delivery, and existing local notifications.
- UI run: six tests, zero failures. Covers permission flow, merchant selection/editing, Other, explicit workspace switching, deleted workspace, and legacy notification routing.
- iOS app/widget device build and Mac Catalyst app build passed with code signing disabled. AppIntents compile as part of these builds.
- GPX XML and increasing timestamps validated. Live MapKit route replay and the locked physical-device check above have not been performed. Full unrelated unit/UI suites were not run; verification was focused on the changed feature and notification integration.

Debug builds retain the latest 100 detection messages under `debug_excursionDetectionTrace` in app UserDefaults and print them with `[ExcursionDetection]`. Inspect these in Xcode to see fix accuracy/age, candidate distances, rejection, and scheduling results. Release builds do not collect this trace. Persisted operational state contains the current session's monitored POIs and last delivered stop for duplicate suppression, not a location history.
