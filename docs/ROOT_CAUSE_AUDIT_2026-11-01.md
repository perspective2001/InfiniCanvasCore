# InfiniCanvas engineering failure audit — 2026-11-01

**Status:** diagnosis of the development process and candidate behavior, not a verified fix to the drawing UI. The user has rejected the current liquid-size appearance and observed a mismatch between its displayed width and actual PencilKit ink. Draft PR #18 must remain unmerged and labeled experimental until device approval.

## Verified evidence

1. **Compilation was repeatedly mistaken for interaction correctness.** Repository PRs #10, #13, #14, #15 and #17 changed the size control, lasso, toolbars, stash and gestures in a short succession without a device-approved visual acceptance step. Each green Xcode build demonstrates compilation, not animation quality or correct Pencil touch routing. Repository AGENTS.md already says one subsystem per change and device-level gate; that process was not followed.
2. **A test eventually measured the discrepancy and failed.** The iOS simulator job in [run 41274050865](https://github.com/perspective2001/InfiniCanvasCore/actions/runs/41274050865) failed `testSelectedScreenWidthRemainsStableAtAllZoomLevels` (requested 20 screen points, actual accepted PencilKit value ≈ 12.83) and `testMarkerPenPencilAndEraserNibScreenSizeAtZoom` (requested 12 but received 8 for pencil at 50% zoom, 15 for highlighter at 200%). Xcode 27 host **compiled successfully** in the same run. Any description of the candidate as passing "all tests" is false.
3. **The nominal-width model ignored PencilKit's permitted range.** `PKInkingTool.InkType.validWidthRange` gives allowed widths for each ink. At 10.2% zoom, 127 apparent screen points requests roughly 1,245 canvas points. Native widths may be capped/adjusted. The liquid preview showed 127 despite the native tool receiving something else; the screenshots visibly proved this. Preserve expressive force/tilt: that is wanted, not a bug. At unsupported extreme widths, either design a tested extended-width pressure-sensitive renderer or disclose the unsupported size; never silently present an impossible preview as exact.
4. **The glass effect was a homemade path, not a verified morph.** The draft's custom `LiquidSizeBubble` plus `LiquidPressureStroke` renders a distinct extruded panel. Apple's documented `GlassEffectContainer`, `glassEffectID` and transition APIs support coordinated material blending; do not call a custom expanding shape Siri-equivalent without reviewing a native captured animation.
5. **Multiple gesture handlers competed for the same touches.** `ContentView.swift` attached high-priority or simultaneous vertical drags to parent toolbar views while child width sliders and thumbnail dragging also used drags. Apple documents that high-priority gestures can take precedence over children. Gesture recognition should be based on the pointer-down location and an explicit interaction state, with exclusive ownership of each touch sequence.
6. **The test environment allowed cross-test saved-clip state.** A stash/organizer regression assumed empty persistent state and failed. The fix changed expectations to allow pre-existing clips. A stronger long-term solution is per-test isolated temporary stores, deterministic fixtures, and restoration invariants, not weaker expectations masking unrelated entries.
7. **Tooling/communication amplified mistakes.** Repeated GitHub contents-API full-file replacements and manual string substitutions were pushed before complete call-site/diff review. Previous PowerShell scripts retriggered full hosted Xcode builds or used brittle latest-run filters; one script failed with an empty run ID and an interactive `gh` prompt. Windows did not compile the iPad app and Sideloadly did not cause the SwiftUI geometry errors.
8. **Safeguards were advisory, not enforced.** AGENTS.md and the playbook already specified strict device verification, but CI had no device-acceptance condition. No repository rulesets were returned by the connected GitHub API; its branch-protection endpoint returned 403, so existing branch-protection state cannot be confirmed.

## Changes proposed in this audit PR

- Add an independent, cheap `Device-accepted for UI changes` PR check. Source-changing PRs require the `device-accepted` label **and** `Device-tested SHA: <exact PR head SHA>` in the PR description, based on explicit user physical-iPad confirmation. New commits invalidate the approval. Documentation/tests/build-workflow-only PRs pass without physical signoff.
- Append `InfiniCanvas-BUILD-INFO.txt` to every unsigned IPA artifact, including exact source SHA, workflow run, and an explicit *not physically verified* status. Automatic source-validated builds are distinguished from manually requested experimental previews.
- Keep this failure audit and the pull-request checklist in the repository so subsequent coding sessions can reload it.

**Limitation:** A new CI job is not an enforced branch rule unless the repository owner makes that status required in GitHub repository rules. Configure a ruleset for `main` to require a pull request, all Apple SDK status jobs, and `Device-accepted for UI changes`, without bypass. The connected tool cannot change rulesets. Do not claim technical prevention is complete before that rule is enabled.

## Mandatory implementation and review sequence for future behavior changes

1. **Freeze the current rejected candidate.** Main remains the last merged source; PR #18 remains Draft. No new UI release by default.
2. **Isolate one failure:** first repair *requested width versus native accepted width* with a genuine dynamic test using `PKInkingTool.width` plus `validWidthRange`. Test zoom 0.102, 0.5, 1, 2 and pressure/tilt separately. Decide how to support sizes beyond native ranges *before* showing them as available.
3. **Only then the upward liquid control:** preserve the exact resting control anchor and selected utensil/color. Use native Liquid Glass containers/transitions where possible. Capture a **real simulator screen** or XCUITest screenshot/video of a small, medium and extreme drag. Validate the appearance with the user before any main merge.
4. **Only then lasso and full toolbar:** one owner for Pencil and finger gestures, coordinate systems unified, tests for moving then dragging *any portion* of selected ink to the entire color/pen toolbar; no ghost duplication, no lost source ink. Tab reorder and drag-to-action tested independently.
5. **Device test before merge:** owner reports pass/fail on same exact candidate SHA with actual Pencil Pro pressure, hover, swipe and lasso, actual saved data, relaunch; not just simulator or in-chat HTML mock.
6. **Review full diff and build provenance:** do not rely on a green prior commit; use exact latest SHA. If red, fix the failing test and rerun. Do not label compiled as device-verified.
7. **Maintain rollback:** preserve installed bundle ID and all saved documents. Never ask to uninstall to update.

## External references

- [Apple: PKInkingTool and force/tilt](https://developer.apple.com/documentation/pencilkit/pkinkingtool-swift.struct)
- [Apple: validWidthRange](https://developer.apple.com/documentation/pencilkit/pkinkingtool-swift.struct/inktype-swift.enum/validwidthrange)
- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Apple: highPriorityGesture](https://developer.apple.com/documentation/swiftui/view/highprioritygesture(_:including:))
- [Apple: simulator screen recording](https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/iOS_Simulator_Guide/InteractingwiththeiOSSimulator/InteractingwiththeiOSSimulator.html)
- [GitHub: required status checks and rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
