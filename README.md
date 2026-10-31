# InfiniCanvasCore · versioned native Swift package

This repository contains the *full* native Infini Canvas feature implementation extracted
from the v0.8 Swift Playgrounds release: PencilKit writing, RestSafe, zoom, lasso,
clip library, CanvasStore, Art Studio, typed notes, notes organization and backups.

## Installation into Swift Playgrounds

Add this repository as a **Swift Package** to the **one permanent**
`InfiniCanvas-Permanent.swiftpm` host app. The host imports `InfiniCanvasCore` and
presents `InfiniCanvasRootView()`. The project source and the native engine remain
SwiftUI/PencilKit; this is not a web wrapper.

Future updates: refresh the **Packages** dependency from Swift Playgrounds and tap
Play. Do not import or overwrite Swift source files manually. Branch `main` is the
update channel, so changes should first be tested before updating it.

The package must be reachable over Git before the host can build. This project
is **prepared locally** and cannot compile in Swift Playgrounds until the GitHub
repository is created and populated.

No user notes, app documents or keys are included in this repository. They are
stored in the installed app's on-device Documents directory.

## Native build verification

The source and manifest are syntax-tested here but Apple SDK linking and native
running require an iPad. Do not erase a proven working app until the permanent host
builds and note persistence is tested.
