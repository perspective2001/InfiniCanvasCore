# Infini Canvas known-good reference and migration forensic record

**The files below are a source-code baseline, NOT a claim of every feature being device-perfect.**

Direct Swift Playgrounds artifact: `InfiniCanvas-Native-v0.8-COMPLETE.zip`, project `InfiniCanvas-Native-v0.8.swiftpm`.
The archive is available in the user's conversation artifacts; do not commit old user drawings to this public repository.

## Source integrity
Each listed direct-project file matches the matching initial `InfiniCanvasCore-repository/Sources/InfiniCanvasCore` source byte-for-byte (SHA-256 of file bytes):
| Source | SHA-256 |
|---|---|
| ArtStudio.swift | 42303fff0b863f271dc34bacf8572274c9632453ea5430e6032bc9d11f1b1640 |
| CanvasStore.swift | f4420c52ccd1a501c0414d8975ef75df121b80c5ed06d8bf4cb68cce98f43674 |
| ClipLibraryView.swift | ae8ea444e4983fe20022c143ed51d5890447cbbabf16df63a8de6ad383d26110 |
| ContentView.swift | e869fd9b7931d9f72346ad9bb358796c25c7e860234e53803498f9d92c94da5b |
| FixedHighlighter.swift | ce8b0afc41d3c7ff4b896762631b00ad7bc704e191825f89b71267ce31b11739 |
| LectureAndOrganizationViews.swift | ceddcff9ad9b13cf0557a363a77b7b3615640bb271307a2e35466c76c75342c1 |
| PencilCanvas.swift | 5a0f2e22725c3a3e446a6897a34571821ecab313b59debe43e7d80d780a690c8 |

## Migration facts
- Original direct host targeted iOS 17.5, while earliest package integration was inconsistent about platform minimum; later normalized to iOS 17.5.
- Permanent host is a separate app package with library dependency. Do not treat library-only CI as a complete app test.
- Rapid post-migration updates introduced new recognizer, zoom, lasso, menu and data changes. The GitHub package mechanism itself did not alter the underlying PencilKit APIs.
- Earlier v0.8 also had potentially problematic RestSafe scroll settings. Use it as a comparison rather than blindly restoring bugs.
- User reported pre-migration writing/palm feel was much better; **on-device UX is the source of truth**.

## Current known failures / uncertainty
- User observed completely white launch after updating 1.0.4, and has not device-confirmed 1.0.5. Do not assume 1.0.5 fixed it merely because a headless CALayer screenshot looked right.
- PencilKit native zoom clamped to 10x in simulator despite 24x/32x requests; true extended zoom is separate engineering work.
- Physical palm rejection, edge focus handle, high-speed lasso and layered art gesture feel remain unverified.
- Verify data/backup location separately for every app host/bundle ID.
