# Native visual and interaction acceptance matrix
*Use for each changed feature, not as a giant project checklist. Never mark a test passed based only on source reading.*

| Scene / check | Source of truth | Automatic evidence | Device acceptance required |
|---|---|---|---|
| Existing toolbar at rest, light/dark | Current accepted device appearance; unchanged control positions/colours | **Native iPad Simulator screenshot** from installed full app; image inspected, compared with last approved reference | Yes for layout changes |
| Upward width control, 15/60/127 screen points | User-provided Siri animation and expected native drawn stroke; full glass moves UP, not an extruded rectangular popup | Native capture from same **production SwiftUI component**, at collapsed/25%/60%/100% expansion; show exact tool, selected color, stroke readout; native simulator clip for transitions | Yes, Pencil/finger drag/release |
| Pen-size visual accuracy at 10.2%, 50%, 100%, 200% zoom | Real accepted `PKInkingTool.width` and actual PencilKit rendered stroke; pressure/tilt variations intentional | Test `validWidthRange` and `PKInkingTool.width * zoom` after requesting size. No silently displaying unsupported 127pt when native width caps. Capture actual stroke on simulator when possible | Yes with Pencil Pro |
| Lasso, zoom and drag into entire existing tool bar | Original source ink and current canvas transform | Geometry/integration tests + real-app screen at before/drag/drop, no offset or duplicate | Yes, repeat drag and stash |
| Move thumbnail between lower bar tabs and header action | Actual upper header destinations and *same* lower tool row | Native scene screenshot at rest/hover/drop; no parent swipe when child drag active | Yes |
| Header swipe versus width/tab gestures | Distinct gesture begin zone; one gesture owner | XCTest gesture state + real host interaction (if possible) | Yes; finger and Pencil |
| Label/trash long-press and data preservation | Persistent clip records and original drawing bytes | Test soft-trash/restore and visual label X | Yes for gestures |
| App launch, saved docs, rollback | Last user-confirmed installed version | Real native app launch + storage tests + IPA source SHA | Yes before merge |

## Evidence artifacts to link in each UI PR
- Source SHA, runner ID and whether this is a **real app render** (not a mock or snapshot drawn through a graphics context).
- `InfiniCanvas-Native-Visual-<SHA>` artifact with full-simulator screenshot, not just test success.
- For morph/animation: frames + actual native video of expansion and collapse captured with `simctl io recordVideo` or XCUITest screen recording. A static screenshot alone is insufficient to approve movement.
- Frame-by-frame review: anchor stays stationary; top contour is rounded with no detachment; inner stroke is color/brush-correct; width does not lie.
- Any uncertainty or device-only limitation explicitly stated. Do not claim a good result simply because a compilation or a geometry smoke test passed.

## Protected/locked areas by default
- Bundle IDs, persistent files/backups, native host entrypoint, working toolbar colors, physical bar heights, undo/redo positions, RestSafe and one-finger pan, current normal pen pressure, existing text notes and saved areas.
- If a task does not explicitly touch one of these, **do not refactor it**. A diff touching unrelated owner files should be split or justified.
- A visual diff that wasn't requested requires user review before merge, even if all CI checks are green.

## Native capture setup (CI)
The iOS 26 PencilKit test job in `.github/workflows/validate-apple-sdk.yml` already runs an iPad simulator; it compiles the actual CI host app, installs it on the working test simulator and captures its rendered screen with `xcrun simctl io screenshot`, then uploads the image artifact. This captures the root app at rest; interaction states still need their own reproducible native capture. If the simulator has no iPad runtime, the screenshot job should fail openly instead of silently fabricating an image. The captured artifact must be actually **opened and looked at** by the assistant before any claimed visual judgment.

## Fast comparison / approvals
Use `docs/CURRENT_WORKING_STATE.md` on every chat resume. Don't re-ingest the full chat. Lock the accepted view and compare the NEW native render against it. If visual differences were not explicitly requested, don't modify those parts. Merge only when the physical device-tested exact SHA is explicitly approved by the user.
