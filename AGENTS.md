# Engineering rules for Infini Canvas (humans and AI coding agents)

Read this before editing or releasing. These rules are persistent repository instructions, **not** a claim that a ChatGPT conversation's global settings have changed.

## Non-negotiable user requirements
- Keep one permanent iPad Swift Playgrounds host, installed documents/data and bundle ID intact.
- App remains fully native SwiftUI + UIKit + PencilKit; no web canvas replacement.
- Regular updates ship through `InfiniCanvasCore` semver tags and the existing Swift package dependency. GitHub pushes do **not** silently update an installed app.
- Protect all user ink, clips, lecture files and Art Studio data. Never delete documents, alter bundle ID, migrate on-disk schema or create a replacement app without explicit review and rollback.
- Regressions in handwriting latency, pen/eraser/lasso, palm interaction, zoom anchor, saving, menus and launch are release blockers.

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
