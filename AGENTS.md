# Engineering rules for Infini Canvas (humans and AI coding agents)

Read this before editing or releasing. These rules are persistent repository instructions, **not** a claim that a ChatGPT conversation's global settings have changed.

## Fast session resume and visual proof (mandatory)

1. Read [current one-page state](docs/CURRENT_WORKING_STATE.md) **first**, then this file and only the affected implementation file(s). Do not reread an entire old conversation or rewrite known-good unrelated code.
2. For changes with visible effects, identify the existing native visual baseline; use the exact-source screenshot artifact created by the existing host validation job. **Open and inspect its pixels** before claiming visual correctness. A compiled/green CI job is not aesthetic proof.
3. For animation, static frames are not enough: record real native motion from the same SwiftUI component (or provide a device-test branch). Do not substitute unrelated mockups or hand-crafted shapes.
4. Write one observable before/after plus **what must not change** from [visual acceptance matrix](docs/VISUAL_ACCEPTANCE_MATRIX.md). Review the diff for collateral UI changes.
5. Approval only after actual iPad check of latest SHA; then update one-page state with what is verified. Preserve user pressure sensitivity and screen-relative width semantics.

## Non-negotiable user requirements
- Keep one permanent iPad Swift Playgrounds host, installed documents/data and bundle ID intact.
- App remains fully native SwiftUI + UIKit + PencilKit; no web canvas replacement.
- Regular updates ship through `InfiniCanvasCore` semver tags and the existing Swift package dependency. GitHub pushes do **not** silently update an installed app.
- Protect all user ink, clips, lecture files and Art Studio data. Never delete documents, alter bundle ID, migrate on-disk schema or create a replacement app without explicit review and rollback.
- Regressions in handwriting latency, pen/eraser/lasso, palm interaction, zoom anchor, saving, menus and launch are release blockers.

## Enforced device-acceptance protocol (2026-11-01)

- For PRs changing native `Sources/InfiniCanvasCore/*.swift`, the `Device-accepted for UI changes` check remains red until the user has actually tested the **same SHA** on their iPad, explicitly confirmed the interaction, and the PR has `device-accepted` plus `Device-tested SHA: <head SHA>` in its description. **Never self-apply an approval based on a simulator test or inferred consent.**
- Branch preview IPAs are experiments, not approved builds. Their downloaded artifact includes `InfiniCanvas-BUILD-INFO.txt` with source SHA and test/approval limitations. Keep rejected drafts unmerged.
- Before proposing a sizing fix, compare the UI preview to the **actual width accepted by `PKInkingTool`**, including each ink type's `validWidthRange`. Test at 10.2% zoom and normal zoom. Pressure and tilt must remain supported.
- The native bubble's appearance needs an actual simulator/iPad recording and user review, not an HTML mock. Never claim a stylized custom shape is Siri's native morph.
- **GitHub repository ruleset must require this status check and the Apple SDK checks on `main`** to make the gate technically non-bypassable. Without ruleset configuration, a failed check is visible but not guaranteed to prevent all merges.

See [November 1 failure audit](docs/ROOT_CAUSE_AUDIT_2026-11-01.md).

## Mandatory development loop
1. Retrieve current repository state and read affected source, the host fixture and [baseline](docs/KNOWN_BASELINE.md). Do not infer from a prior summary.
2. Write one observable acceptance criterion and a failing **targeted** regression test when practical; don't confuse a mocked view with a physically operated Apple Pencil.
3. Change one subsystem at a time in a named branch. Preserve native APIs and original behaviour unless the change is necessary.
4. Verify diff, formatting, deployment target, app permissions, backwards-compatible data, and every touched call site.
5. Run inexpensive syntax/geometry/unit tests first; then host + core build with current Xcode; then simulator UI launch and regression tests.
6. Require green CI for **the latest commit**, not the previous commit. Never merge a red or pending PR, never publish a version before test completion.
7. Do an on-iPad acceptance check for physical gestures, real Pencil handwriting, multitouch and long-running use. No amount of simulator testing proves those.
8. Publish a patch version only after that gate and preserve the earlier release tag. Update changelog and rollback notes. Do not call a release stable while the user reports a white screen.
9. If blocked, report verified facts, probable hypotheses, and what remains untested. Do not tell the user to reinstall or delete anything reflexively.

## Efficient agent practices
- Diagnose at the boundary: launch host vs package resolution vs code compilation vs rendered UI vs touch input vs persistence.
- Gather related source in batches, compare to Git history and the unmodified v0.8 baseline; avoid speculative line edits.
- Use one coherent feature branch and one full candidate test cycle; avoid a fresh expensive build for each cosmetic edit.
- Prefer native gestures, one owner for each touch stream; never duplicate pinch/pan recognizers without device-level proof.
- Use deterministic fixtures and tests for all previously reported defects. When a bug recurs, improve the test *before* shipping a patch.
- Measure actual frame times and memory before claiming fast, smooth, or Goodnotes-equivalent behaviour.
- Record limitations as issues; do not invent capabilities. Native PKCanvasView tested at 10x, not the earlier advertised 24x.
- For AI coding: prefer scoped context, explicit constraints, small reviewed diffs, tool-based verification, and critical human-in-the-loop acceptance. Fancy 'super prompts' do not replace tests.

## Architecture checkpoints
- `Sources/InfiniCanvasCore/`: implementation of native engine and public root view.
- `Tests/InfiniCanvasCoreTests/`: unit and PencilKit integration tests.
- `Tests/GeometrySmoke/`: deterministic transform smoke.
- `IntegrationHost/InfiniCanvasPermanent.swiftpm/`: *CI-only* twin of existing host; do not ask user to reinstall it.
- `docs/KNOWN_BASELINE.md`: preserved source hashes, known working and broken behaviours.
- `docs/RELEASE_AND_ROLLBACK.md`: build, physical acceptance, safety and tag policy.
- `docs/ENGINEERING_PLAYBOOK.md`: shared evidence-first engineering loop, code-review criteria and cost-conscious verification.

## Release status
As of 2026-10-31, 1.0.5 is the newest tag but **not user-confirmed working**. Keep it as the current source reference; no new version should be tagged until physical white-screen debugging and launch acceptance pass.
