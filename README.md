# Infini Canvas Core — native iPad Swift package

This public repository contains **source code** for a native SwiftUI/UIKit/PencilKit iPad app. It does **not** store the user's ink, recordings, clips or backups.

## App structure
- `InfiniCanvasCore`: native library. Exposes `InfiniCanvasRootView`.
- Installed project: **`InfiniCanvas-Permanent-Prelinked.swiftpm`** (on the user's iPad). It is a separate app, has a stable bundle ID and uses the semver range `from: "1.0.0"`.
- `IntegrationHost/InfiniCanvasPermanent.swiftpm/`: CI-only mirror of that app's entry point, manifest, bundle ID and entitlements, with a local package path for testing the **current PR** source. Xcode 27 compiles that exact entry-point source through a small XcodeGen iOS application; the special AppleProductTypes Playgrounds manifest is checked structurally because vanilla Xcode SwiftPM cannot import AppleProductTypes. It is **not** a new project for the user.

## Updating the existing iPad Playground
1. In Swift Playgrounds open the same `InfiniCanvas-Permanent-Prelinked` document, never delete it to update.
2. Long-press **Packages** -> **Update All Package Dependencies**.
3. Tap **Play**. Swift Playgrounds resolves/builds the eligible tagged package version.

GitHub pushes do not silently update the iPad binary. A package has no home-screen installation or code-signing powers by itself; those require separately distributing/signing the application. Changing bundle IDs or entitlements also requires careful host changes.

## Verification and release policy
- Read [AGENTS.md](AGENTS.md) before agent/human coding edits and [the original baseline](docs/KNOWN_BASELINE.md) before changing writing gestures.
- Run CI in parallel: Xcode 27 compiles native package + actual entry-point source as an iOS application; the iOS 26 compiler runs PencilKit/SwiftUI integration tests closer to the current Swift Playgrounds editor SDK. AppleProductTypes manifests cannot be directly compiled by vanilla Xcode SwiftPM. Headless Apple Pencil tests do not prove physical-device handwriting, palm rejection or menu gestures.
- Keep changes on PR branches. Publish no package tag from a red or pending Xcode 27 CI run.
- Read [release and rollback guide](docs/RELEASE_AND_ROLLBACK.md).
- **1.0.5 is the latest tagged source, not a user-verified stable release**; the white-screen complaint on the actual device needs an on-iPad acceptance check.
- Direct v0.8 Swift files match the initial migration copy; post-migration gesture and infrastructure changes caused regressions.

## Capabilities and limits
- PencilKit pen/pencil/highlighter, lasso, clips, study/lecture workflow, Art Studio.
- Native PKCanvasView zoom reached a measured 10x in simulator even when values above 10 were requested. Extended rendering architecture is tracked separately.
- Native iPadOS APIs remain available inside a Swift package subject to the **host's** SDK, permissions, deployment target and package build settings.
- App data remains local to the installed app's private sandbox; never change the bundle ID or delete the app as an attempted cache fix.

## Recovery and prior sources
Earlier native `.swiftpm` projects (including v0.8) are archived with the conversation and their SHA-256 hashes are recorded in [KNOWN_BASELINE](docs/KNOWN_BASELINE.md). They are forensic baselines, not interchangeable install packages or automatic data migrations.
