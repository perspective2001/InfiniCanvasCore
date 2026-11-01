## One user-visible change and one acceptance criterion

<!-- State the single behavior being changed. Avoid combining layout, lasso, zoom, data migration and gestures in one candidate. -->

- Before:
- Expected after:
- What must remain unchanged:

## Exact-SHA verification

- Candidate HEAD SHA:
- Cheap preflight:
- Xcode 27 native iPad host build:
- iOS 26 PencilKit unit/integration tests:
- Actual native screenshot/video reviewed:
- Saved drawings, clips and rollback verified:

## Native Pencil interaction / iPad acceptance

<!-- DO NOT mark this accepted because the app compiled, an HTML mock worked or simulator tests passed.
     Test the same commit installed on the real iPad and get explicit user acceptance.
     For Sources/InfiniCanvasCore/*.swift changes, the Device-accepted for UI changes check requires
     both a device-accepted label and exact text of the form "Device-tested SHA: <40-char SHA>".
     New source commits invalidate the acceptance. -->

- Status: **UNTESTED ON DEVICE**
- Tested behavior: (pen width at current zoom, pressure/tilt, lasso, swipe ownership, full-bar stash, launch/save/relaunch as relevant)
- Device-tested SHA: PENDING

## Provenance / rollout

- IPA artifact and `InfiniCanvas-BUILD-INFO.txt` reviewed:
- Last confirmed-working device build protected:
- No bundle-ID changes, uninstall instructions or destructive schema modifications:
- User approved merging into `main`: **NO / YES with explicit confirmation**
