# Release engineering and data-safety gates

## Source and app ownership
- `InfiniCanvasCore` is native reusable Swift source. Public package version tag `1.0.x` identifies immutable code.
- Real installed Swift Playgrounds host is `InfiniCanvas-Permanent-Prelinked.swiftpm` with bundle ID `com.perspective2001.infini-canvas.native`, product `InfiniCanvasCore`, and semver dependency `from: "1.0.0"`.
- `IntegrationHost/` is the **CI twin**, not a replacement user app. It uses a local relative package path to exercise current PR code. Keep all other app identity/capabilities in sync with the existing host.
- The iPad does **not** automatically install a new binary on a GitHub push. The user must update package dependencies, compile/run within Swift Playgrounds; Home Screen launch/signing is a separate distribution question.

## CI release gate
1. Feature work on branch, one scoped review; don't push broken intermediate work to main.
2. Latest SHA passes Xcode 27 native tests, actual root render test, and host application integration build.
3. Test data persistence + backwards-compatible restore; no destructive migrations.
4. Compare workflows against prior version at the touched feature boundary.
5. Real iPad: launch; 15 pen/pencil strokes; restSafe finger scroll; pinch/anchor; lasso pen+pencil; undo/redo; right-edge paper only; pen width; background/relaunch; backup export; Art Studio layer save.
6. Only then publish semver patch and refresh the app with `Packages -> Update All Package Dependencies`. If white-screen issue persists, **do not** label a release fixed. Always maintain last device-verified tag separately from latest source tag.

## Rollback
- Never delete the iPad app or original .swiftpm folder to roll back source.
- First export an on-device complete backup if app is accessible. Existing drawing files are in the app's private document container and depend on app identity.
- For a tag regression, create a separately tested recovery tag from a known code commit (a semver-compatible `1.x` tag), or temporarily change the existing host's package requirement **only after** a backup and explicit device recovery plan.
- `Update All Package Dependencies` moves forwards to eligible versions; it is not a downgrade button.
- The old direct v0.8 sources are an archived reference, not evidence that the current host can load the old data unchanged.

## Performance gate
- 4x project geometry tests ≠ smooth Apple Pencil input; use physical iPad latency and profiling for pressure/tilt/palm.
- Baseline target: no unexpected gesture mode switches, no stroke flicker, correct zoom anchor, no clipped toolbar controls, no loss on app background.
- Optimize only after measuring slow path; do not refactor the entire drawing engine in the same PR as an unrelated UX change.

## Toolchain and cost
- Use `xcode-27` for authoritative current SDK. An older SDK can be an optional compatibility check, not the only gate.
- GitHub Actions consume runner resources. Keep docs-only changes out of expensive jobs; cancel superseded PR runs; manually gate costly release CI if needed.
- Tags should never be created on a red or pending commit. Historical auto-tag workflow can publish an unvalidated main commit, so do not bump SWIFT_PACKAGE_VERSION before the complete gate.
