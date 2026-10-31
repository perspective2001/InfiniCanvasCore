# InfiniCanvasCore — native iPad engine

This is the **updatable Swift package** for the personal **Infini Canvas** iPad app. It contains the v0.8 SwiftUI / UIKit / PencilKit source: handwriting, RestSafe, lasso, zoom, clips, study tools, lecture recordings, organization, and Art Studio.

The permanent Swift Playgrounds host is a separate minimal `.swiftpm` app that imports the package:

```swift
import SwiftUI
import InfiniCanvasCore

@main struct InfiniCanvasApp: App {
    var body: some Scene {
        WindowGroup { InfiniCanvasRootView() }
    }
}
```

The host's `Package.swift` points to `https://github.com/perspective2001/InfiniCanvasCore.git` on branch `main` and uses the `InfiniCanvasCore` library product.

## First installation (one time)

1. Extract `InfiniCanvas-Permanent-Install-Once.zip` in the iPad Files app.
2. Open **`InfiniCanvas-Permanent.swiftpm`** through **Swift Playgrounds → Browse**.
3. Allow Swift Playgrounds to fetch the Swift package. If prompted, select the `InfiniCanvasCore` product.
4. Press **Play**, then verify writing, lasso, RestSafe, autosaving, and reopening with **test ink**.
5. Keep your previously working app until you confirm the new permanent host compiles and runs. Initial installation is **not** guaranteed to transfer old on-device drawings.

## Future code updates

1. Updates are committed to `main` in this repository (ideally after testing).
2. On iPad, open the **same permanent Playground project**.
3. Long-press **Packages** in the left sidebar and choose **Update All Package Dependencies**.
4. Tap **Play**. No new app ZIP is needed for package-only changes.

Updating is **not** automatic in the background. Changing host permissions, the bundle ID, or the app's own dependency declaration may require a rare host update.

## Source, privacy and verification

Only application source is stored here — never handwritten notes or backups. User content is saved on-device by the native app; back up data before major migrations. Swift source parses, the package manifest passes `swift package dump-package`, and uploaded GitHub file hashes were verified against the original local files. **Full iPadOS SDK compilation and Apple Pencil behavior still require testing in Swift Playgrounds.**
