# CURRENT WORKING STATE — InfiniCanvas
*Always read this one page before an InfiniCanvas edit; update only when a decision or verified state changes. Last updated 2026-11-01.*

## Current reality — never infer from a former chat
- **Production branch:** `main`. Do not treat the most recent commit, green compilation, or latest IPA as a known-good device build. `docs/KNOWN_BASELINE.md` records the device baseline.
- **Experimental drawing work:** Draft [PR #18](https://github.com/perspective2001/InfiniCanvasCore/pull/18) remains **REJECTED and unmerged**. User's real screenshot showed huge `127pt` morph preview with a hairline stroke at 10.2% zoom, and a bad box/funnel instead of a Siri-like morph. The simulator width tests also failed. Don't release it as accurate.
- **Current priority:** visual observability and small, reliable iteration first; *then* native Liquid Glass morph and accurate sizing. Keep those changes on a different branch from process work.
- **Visual capture now PROVEN:** PR #21 (merged at `b81d69f00ceaeb14994a5facda64b664a4570159`) added a native iPad screenshot to the existing iOS 26 PencilKit runner. Validation [run 41328989188](https://github.com/perspective2001/InfiniCanvasCore/actions/runs/41328989188) passed all 3 jobs and produced artifact `InfiniCanvas-Native-Visual-a9e2de1262e1fdfeea2f39db71d5ea0d01fc6d7b`, artifact ID `13092941083`. The connector downloaded it, and I **opened the PNG and inspected its real pixels** (2064×2752). It shows InfiniCanvas's toolbars, blank canvas, status bar. This proves native **resting portrait appearance** and the image-access pipeline only; **LANDSCAPE and EXPANDING BUBBLE/MOTION NOT YET CAPTURED**.
- **Next hard gate before any Siri morph merge:** capture the *actual shared SwiftUI morph component* at collapsed, 25%, 60%, 100% progress on the iPad simulator (prefer landscape), and a genuine native transition recording if possible. Compare personally to user's Siri video, visibly reject box/funnel/mushroom shapes before asking user for another IPA. Capturing only a stable root screenshot is not motion approval.

- **No known matching Siri visual yet.** A static SwiftUI screenshot may inspect appearance, but a short **native recording of the actual interaction** is required before making claims about motion.
- **Pressure/tilt sensitivity stays.** A selected apparent tool width should hold constant at any canvas zoom for *new* ink. At deep zoom and large widths, `PKInkingTool.InkType.validWidthRange` may cap the requested native nib. Never show a physically impossible requested size as an actual size. Read back actual native width; choose either an honestly limited option or a separately tested expressive large-width implementation.

## Exact user visual/gesture contract (not suggestions)
1. **Pen width:** original horizontal width pill stays in the SAME place in SAME slim toolbar. Dragging *from it* upward raises/morphs the WHOLE translucent glass bubble, like the user's Siri reference; pressure-like growing line within the bubble uses exact selected tool and color. Line becomes round at the top at very large widths. Releasing collapses the glass, keeps chosen screen-size nib; tap separately opens detail settings. It must NOT look like a detached rectangular popup, mushroom or funnel. Normal Pencil pressure may make real strokes thicker.
2. **Toolbar:** leave positions/colors/proportions of all controls untouched unless specifically requested. Header contains Learn, ChatGPT, Organize beside InfiniCanvas/RestSafe. Entire existing lower pen/color toolbar is a drop target for selected ink; NOT a tiny right-corner pill or a new row. Incoming selection shrinks toward its nearest contact point; placed large thumbnail tabs live inline and can be rearranged/reordered, dragged to header actions/trash or long-pressed for X.
3. **Gestures:** swipe unused header/toolbar up to tuck top header, down to reveal. NEVER steal Pencil-width drag or lasso/mini-tab drag. Double tap right edge toggles paper-only. No inadvertent copy/paste menu.
4. **Lasso:** move handwriting without ghost ink, huge offset, destroyed selection or loss of editability; preserve original ink and documents. User's organizer exists far away *on the same canvas* with ordered saved clips, tap navigates there and Pencil drop files clips.
5. **Delete:** labels including auto-generated LING categorization, inserted objects and clip tabs can be removed intentionally with a long-press X or top trash, with recoverable soft-deletion and preserved source ink.
6. **Hardware:** Windows PC + iPad Pro M5, Pencil Pro, free Apple ID, Sideloadly. GitHub Actions compiles unsigned IPA on hosted Mac; Windows PowerShell should download a matching completed artifact **without retriggering a build** by default. Do not change bundle ID or uninstall installed preview.

## The fast 5-step iteration loop
1. **Read only** this page + `AGENTS.md` and files that OWN the requested behaviour. Identify exact baseline, source commit, and what stays untouched.
2. **Contract:** record one before/after and the negative case. Before touching code, identify visual reference and a *native* scene/state to inspect. No re-implementation of adjacent good components.
3. **Modify just one subsystem** on a named branch. Run cheap preflight and focused geometry/API tests.
4. **Real visual evidence:** use the already-running iPad SDK job, which builds the CI host and uploads simulator screenshot artifact `InfiniCanvas-Native-Visual-<SHA>`. For animation/gestures use deterministic real-app state capture/XCUITest or a branch IPA with Pencil hardware; don't approve from an HTML mock, simulated screenshot of a different component, or a description of code.
5. **Audit:** compare *actual screenshot/movie* to user's reference and to previous accepted appearance; inspect logs plus exact-source SHA; fix failures before asking user. Request explicit on-device review only when simulator visuals and relevant tests are good. Merge only after device approval per check gate.

## Evidence vocabulary
`implemented` != `compiled` != `simulator screenshot inspected` != `physical Pencil verified` != `device-approved`. A step only counts when its artifact/CI run/SHA is identified.

## Quick resume links
- [Engineering contract](../AGENTS.md)
- [Visual/behaviour acceptance matrix](VISUAL_ACCEPTANCE_MATRIX.md)
- [Failure investigation](ROOT_CAUSE_AUDIT_2026-11-01.md)
- [Known baseline](KNOWN_BASELINE.md)
- [Apple preview and glass documentation](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)

**Efficiency rule:** On subsequent chats, retrieve this file and the relevant owner file, not the entire previous chat or all repo history. Update the state card when decisions change; don't append every test log to it.
