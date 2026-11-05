# Excursion Mode location replay

These public-area simulation fixtures exercise South Bay Village shopping center in Torrance, California. They contain no home coordinate and no McDonald’s override.

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

For a live check, select a narrow category such as Gas Station in All Categories, replay a dwell, and confirm the eligible candidate list contains only that category. Repeat with Select All and Include uncategorized places enabled. Merchant availability and classification depend on MapKit, so an omitted or unclassified business may not appear while Include uncategorized places is off. All fixtures now have waypoint gaps of at most 15 seconds, including approach, adjacent movement, and departure segments. Added points linearly interpolate the existing path while preserving original waypoints, total duration, and each segment’s intended speed. XML/timestamp validation confirms the cadence is suitable for the default 22.5-second gap if the simulator emits fresh callbacks as expected.

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
