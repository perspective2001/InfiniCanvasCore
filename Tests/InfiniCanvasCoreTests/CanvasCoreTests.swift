import XCTest
import SwiftUI
import UIKit
import PencilKit
@testable import InfiniCanvasCore

@MainActor
final class CanvasCoreTests: XCTestCase {
    private func makeStroke(_ kind: PKInkingTool.InkType, x: CGFloat, y: CGFloat) -> PKStroke {
        let ink = PKInk(kind, color: .black)
        let points: [PKStrokePoint] = [
            PKStrokePoint(location: CGPoint(x: x - 18, y: y - 8), timeOffset: 0,
                          size: CGSize(width: 4, height: 4), opacity: 1,
                          force: 0.5, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: x + 18, y: y + 8), timeOffset: 0.08,
                          size: CGSize(width: 4, height: 4), opacity: 1,
                          force: 0.5, azimuth: 0, altitude: .pi / 2)
        ]
        return PKStroke(ink: ink,
                        path: PKStrokePath(controlPoints: points, creationDate: .now),
                        transform: .identity, mask: nil)
    }

    func testPKDrawingAndArtDocumentRoundTrip() throws {
        let drawing = PKDrawing(strokes: [
            makeStroke(.pen, x: 150, y: 100),
            makeStroke(.pencil, x: 190, y: 120),
            makeStroke(.marker, x: 230, y: 150)
        ])
        let restored = try PKDrawing(data: drawing.dataRepresentation())
        XCTAssertEqual(restored.strokes.count, 3)
        let layer = ArtworkLayer(name: "QA", drawing: drawing.dataRepresentation())
        let document = ArtworkDocument(layers: [layer], selected: layer.id)
        let decoded = try JSONDecoder().decode(ArtworkDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded.layers.count, 1)
        XCTAssertEqual(try PKDrawing(data: decoded.layers[0].drawing).strokes.count, 3)
    }

    func testLassoCapturesPenPencilAndMarkerAtZoom() throws {
        let store = CanvasStore()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let canvas = PKCanvasView(frame: window.bounds)
        canvas.minimumZoomScale = 0.045
        canvas.maximumZoomScale = 24
        canvas.contentSize = CGSize(width: 100000, height: 100000)
        window.addSubview(canvas)
        let overlay = UIView(frame: window.bounds)
        window.addSubview(overlay)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        store.attach(canvas)

        let drawing = PKDrawing(strokes: [
            makeStroke(.pen, x: 1000, y: 1000),
            makeStroke(.pencil, x: 1060, y: 1000),
            makeStroke(.marker, x: 1120, y: 1000)
        ])
        canvas.drawing = drawing

        for zoom: CGFloat in [0.25, 1, 3] {
            store.clearSelection()
            canvas.setZoomScale(zoom, animated: false)
            canvas.setContentOffset(CGPoint(x: 950 * canvas.zoomScale - 250,
                                            y: 950 * canvas.zoomScale - 250), animated: false)
            let topLeft = CanvasGeometry.viewportPoint(
                drawing: CGPoint(x: 940, y: 940),
                offset: canvas.contentOffset, scale: canvas.zoomScale)
            let bottomRight = CanvasGeometry.viewportPoint(
                drawing: CGPoint(x: 1180, y: 1060),
                offset: canvas.contentOffset, scale: canvas.zoomScale)
            let polygon = [
                topLeft,
                CGPoint(x: bottomRight.x, y: topLeft.y),
                bottomRight,
                CGPoint(x: topLeft.x, y: bottomRight.y)
            ]
            store.captureLasso(polygon, from: overlay)
            XCTAssertTrue(store.selectionActive, "All PencilKit stroke types must be selected at zoom \(zoom); status: \(store.status)")
            XCTAssertEqual(store.latestClip?.strokeCount, 3)
        }
    }
    func testStashAndOrderedOrganizerAreNonDestructiveAndBackedUp() throws {
        let store = CanvasStore()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let canvas = PKCanvasView(frame: window.bounds)
        canvas.minimumZoomScale = 0.045
        canvas.maximumZoomScale = 10
        canvas.contentSize = CGSize(width: 12000, height: 12000)
        window.addSubview(canvas)
        let overlay = UIView(frame: window.bounds)
        window.addSubview(overlay)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        store.attach(canvas)
        store.tool = .capture

        let ink = PKDrawing(strokes: [makeStroke(.pen, x: 230, y: 250)])
        canvas.drawing = ink
        let polygon = [CGPoint(x: 160, y: 185), CGPoint(x: 310, y: 185),
                       CGPoint(x: 310, y: 310), CGPoint(x: 160, y: 310)]
        store.captureLasso(polygon, from: overlay)
        let clip = try XCTUnwrap(store.latestClip)
        XCTAssertEqual(clip.strokeCount, 1)
        XCTAssertTrue(store.selectionActive)
        let prior = canvas.drawing.dataRepresentation()

        let drag = store.beginSelectionDrag(in: overlay)
        XCTAssertNotNil(drag)
        XCTAssertEqual(canvas.drawing.strokes.count, 0,
                       "Selected strokes are detached ONLY for live drag preview")
        XCTAssertTrue(store.stashSelectedInk())
        XCTAssertEqual(canvas.drawing.strokes.count, 1,
                       "Stashing must restore original ink rather than deleting it")
        XCTAssertEqual(canvas.drawing.dataRepresentation(), prior)
        XCTAssertTrue(store.stashedClips.contains(where: { $0.id == clip.id }))

        XCTAssertTrue(store.addToSpatialOrganizer(clip.id))
        XCTAssertTrue(store.addToSpatialOrganizer(clip.id))
        XCTAssertFalse(store.stashedClips.contains(where: { $0.id == clip.id }))
        XCTAssertEqual(store.spatialOrganizerClips.filter { $0.id == clip.id }.count, 1,
                       "Repeated drops must never duplicate the same clip")
        XCTAssertEqual(store.spatialOrganizerClips.last?.id, clip.id,
                       "New clip must append to the organizer's pre-existing order")
        XCTAssertNotNil(store.spatialOrganizerArea)

        let backupURL = try XCTUnwrap(store.exportCompleteBackup())
        let backup = try JSONDecoder().decode(
            CompleteBackup.self, from: Data(contentsOf: backupURL))
        XCTAssertEqual(backup.index.organizedClipIDs?.last, clip.id)
        XCTAssertEqual(backup.index.organizedClipIDs?.filter { $0 == clip.id }.count, 1)
        XCTAssertNotNil(backup.index.organizerAreaID)
        XCTAssertNotNil(try PKDrawing(data: backup.drawing).strokes.first)
        window.isHidden = true
    }

    func testSoftDeleteAreaAndSavedThumbDoesNotEraseInkAndCanRestore() throws {
        let store = CanvasStore()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let canvas = PKCanvasView(frame: window.bounds)
        canvas.minimumZoomScale = 0.045
        canvas.maximumZoomScale = 10
        canvas.contentSize = CGSize(width: 12000, height: 12000)
        window.addSubview(canvas)
        let overlay = UIView(frame: window.bounds)
        window.addSubview(overlay)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        store.attach(canvas)
        store.tool = .capture

        canvas.drawing = PKDrawing(strokes: [makeStroke(.pen, x: 220, y: 245)])
        let originalInk = canvas.drawing.dataRepresentation()
        store.addArea("LING Categorization")
        let area = try XCTUnwrap(store.areas.last)
        XCTAssertEqual(area.title, "LING Categorization")

        let boundary = [CGPoint(x: 140, y: 175), CGPoint(x: 320, y: 175),
                        CGPoint(x: 320, y: 315), CGPoint(x: 140, y: 315)]
        store.captureLasso(boundary, from: overlay)
        let clip = try XCTUnwrap(store.latestClip)
        XCTAssertTrue(store.stashSelectedInk())
        XCTAssertTrue(store.stashedClips.contains(where: { $0.id == clip.id }))
        XCTAssertTrue(store.addToSpatialOrganizer(clip.id))
        XCTAssertTrue(store.spatialOrganizerClips.contains(where: { $0.id == clip.id }))

        store.deleteClip(clip)
        XCTAssertFalse(store.stashedClips.contains(where: { $0.id == clip.id }))
        XCTAssertFalse(store.spatialOrganizerClips.contains(where: { $0.id == clip.id }))
        XCTAssertTrue(store.discardedClips.contains(where: { $0.id == clip.id }))
        store.deleteArea(area)
        XCTAssertFalse(store.activeAreas.contains(where: { $0.id == area.id }))
        XCTAssertTrue(store.discardedAreas.contains(where: { $0.id == area.id }))
        XCTAssertEqual(canvas.drawing.dataRepresentation(), originalInk,
                       "Deleting thumbnails and categorization must preserve all Pencil ink")

        store.restoreArea(area)
        store.restoreClip(clip)
        XCTAssertTrue(store.activeAreas.contains(where: { $0.id == area.id }))
        XCTAssertTrue(store.activeClips.contains(where: { $0.id == clip.id }))
        XCTAssertEqual(canvas.drawing.dataRepresentation(), originalInk)
        window.isHidden = true
    }

    func testLiquidPressureStrokeHasRoundFullWidthTipInsideGlass() {
        for nib: CGFloat in [2.5, 15, 60, 127] {
            // Geometry of the *actual production SwiftUI Shape*, not an HTML mock.
            let bounds = CGRect(x: 0, y: 0, width: max(92, nib + 48), height: 140)
            let shape = LiquidPressureStroke(tipWidth: nib).path(in: bounds).boundingRect
            XCTAssertFalse(shape.isEmpty)
            XCTAssertGreaterThanOrEqual(shape.minX, -0.01)
            XCTAssertLessThanOrEqual(shape.maxX, bounds.maxX + 0.01)
            XCTAssertGreaterThanOrEqual(shape.minY, -0.01)
            XCTAssertLessThanOrEqual(shape.maxY, bounds.maxY + 0.01)
            XCTAssertEqual(shape.width, nib, accuracy: 2,
                           "Uppermost rounded mark should show selected on-screen width")
        }
    }

    func testNativeMorphPlacementPreservesScreenBoundsAndOriginalPillAnchor() {
        for viewportWidth: CGFloat in [768, 834, 1024, 1366] {
            for selectedWidth: CGFloat in [2.5, 15, 60, 127, 160] {
                let trigger = CGRect(x: viewportWidth - 137, y: 111,
                                     width: 84, height: 44)
                let placement = WidthMorphPlacement(
                    viewportWidth: viewportWidth,
                    trigger: trigger, selectedWidth: selectedWidth,
                    travel: 290)
                let left = placement.centerX - placement.width / 2
                let right = placement.centerX + placement.width / 2
                XCTAssertGreaterThanOrEqual(left, 8 - 0.01)
                XCTAssertLessThanOrEqual(right, viewportWidth - 8 + 0.01)
                XCTAssertEqual(left + placement.anchorX, trigger.midX,
                               accuracy: 0.01, "Bubble base must stay on the original stationary pill")
                XCTAssertGreaterThanOrEqual(placement.centerY - placement.height / 2,
                                            29.9, "Don't clip into the status bar")
            }
        }
    }

    func testNominalToolWidthMatchesActualPencilKitConfiguration() {
        let store = CanvasStore()
        store.tool = .pen
        store.setSelectedScreenNibWidth(8)
        XCTAssertEqual(store.nominalToolWidth, 8)
        store.tool = .pencil
        store.setSelectedScreenNibWidth(8)
        XCTAssertEqual(store.nominalToolWidth, 8)
        store.tool = .marker
        store.fixedHighlighter = false
        store.setSelectedScreenNibWidth(32)
        XCTAssertEqual(store.nominalToolWidth, 32,
                       "Preview matches native marker nib after applying its 4× width multiplier")
        store.fixedHighlighter = true
        XCTAssertEqual(store.nominalToolWidth, store.markerWidth,
                       "Fixed vertical highlighter uses its own nib geometry")
        store.tool = .eraser
        store.setSelectedScreenNibWidth(46)
        XCTAssertEqual(store.nominalToolWidth, 46)
    }

    func testStashedTabsReorderWithoutChangingCanvasInk() throws {
        let store = CanvasStore()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let canvas = PKCanvasView(frame: window.bounds)
        canvas.minimumZoomScale = 0.045
        canvas.maximumZoomScale = 10
        canvas.contentSize = CGSize(width: 12000, height: 12000)
        window.addSubview(canvas)
        let overlay = UIView(frame: window.bounds)
        window.addSubview(overlay)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        store.attach(canvas)
        store.tool = .capture
        canvas.drawing = PKDrawing(strokes: [makeStroke(.pen, x: 200, y: 200)])
        let original = canvas.drawing.dataRepresentation()
        let outline = [CGPoint(x: 145, y: 150), CGPoint(x: 265, y: 150),
                       CGPoint(x: 265, y: 255), CGPoint(x: 145, y: 255)]
        store.captureLasso(outline, from: overlay)
        let first = try XCTUnwrap(store.latestClip)
        XCTAssertTrue(store.stashSelectedInk())
        store.captureLasso(outline, from: overlay)
        let second = try XCTUnwrap(store.latestClip)
        XCTAssertTrue(store.stashSelectedInk())
        XCTAssertEqual(store.stashedClips.suffix(2).map(\.id), [first.id, second.id])
        XCTAssertTrue(store.moveStashedClip(second.id, before: first.id))
        XCTAssertEqual(store.stashedClips.suffix(2).map(\.id), [second.id, first.id])
        XCTAssertFalse(store.moveStashedClip(second.id, before: second.id))
        XCTAssertEqual(canvas.drawing.dataRepresentation(), original,
                       "Reordering tabs must never modify source handwriting")
        window.isHidden = true
    }

    func testStashShrinksOnCornerApproachWithoutFalseFarAwayHit() {
        let target = CGRect(x: 780, y: 105, width: 150, height: 38)
        let far = CGRect(x: 100, y: 500, width: 120, height: 90)
        let near = CGRect(x: 680, y: 162, width: 80, height: 50)
        let touching = CGRect(x: 760, y: 140, width: 30, height: 30)
        let overlapping = CGRect(x: 805, y: 110, width: 50, height: 25)
        XCTAssertEqual(LassoTouchView.proximity(of: far, to: target), 0)
        XCTAssertGreaterThan(LassoTouchView.proximity(of: near, to: target), 0)
        XCTAssertGreaterThan(LassoTouchView.proximity(of: touching, to: target),
                             LassoTouchView.proximity(of: near, to: target))
        XCTAssertEqual(LassoTouchView.proximity(of: overlapping, to: target), 1)
        XCTAssertEqual(LassoTouchView.proximity(of: overlapping, to: .null), 0)
    }

    private func assertScreenWidthIsActuallyRepresented(
        _ store: CanvasStore, canvas: PKCanvasView, overlay: UIView,
        desired: CGFloat, file: StaticString = #filePath, line: UInt = #line
    ) {
        if store.needsScreenWidthInkOverlay {
            // Native ink clamped. The custom path must store the user-facing
            // screen-space size, not just change a UI number.
            let before = canvas.drawing.strokes.count
            let sampleTime = Date().timeIntervalSince1970
            let points = [
                ScreenWidthInkSample(location: CGPoint(x: 300, y: 325),
                                     time: sampleTime, force: 0.5,
                                     azimuth: 0, altitude: .pi / 2),
                ScreenWidthInkSample(location: CGPoint(x: 400, y: 325),
                                     time: sampleTime + 0.01, force: 0.5,
                                     azimuth: 0, altitude: .pi / 2)
            ]
            store.commitScreenWidthStroke(points, from: overlay)
            XCTAssertEqual(canvas.drawing.strokes.count, before + 1, file: file, line: line)
            guard let stroke = canvas.drawing.strokes.last, stroke.path.count > 0 else {
                XCTFail("PencilKit did not preserve the custom editable stroke", file: file, line: line)
                return
            }
            XCTAssertEqual(stroke.path[0].size.width * canvas.zoomScale,
                           desired, accuracy: max(0.3, desired * 0.02),
                           "Actual editable PencilKit point size must equal requested screen size",
                           file: file, line: line)
        } else if let native = canvas.tool as? PKInkingTool {
            XCTAssertEqual(native.width * canvas.zoomScale, desired, accuracy: 0.12,
                           "Use native low-latency PencilKit when its actual accepted size works",
                           file: file, line: line)
        }
    }

    func testSelectedScreenWidthRemainsStableAtAllZoomLevels() throws {
        let store = CanvasStore()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let canvas = PKCanvasView(frame: window.bounds)
        canvas.minimumZoomScale = 0.045
        canvas.maximumZoomScale = 10
        canvas.contentSize = CGSize(width: 12000, height: 12000)
        window.addSubview(canvas)
        let overlay = UIView(frame: window.bounds)
        window.addSubview(overlay)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        store.attach(canvas)
        store.tool = .pen
        store.setSelectedScreenNibWidth(20)
        for zoom: CGFloat in [0.102, 0.5, 1, 2, 5] {
            store.zoomTo(zoom)
            XCTAssertEqual(store.zoom, zoom, accuracy: 0.02)
            XCTAssertEqual(store.selectedScreenNibWidth, 20, accuracy: 0.02)
            XCTAssertEqual(store.strokeWidth, 20 / zoom, accuracy: 0.03)
            assertScreenWidthIsActuallyRepresented(
                store, canvas: canvas, overlay: overlay, desired: 20)
        }
        // Changing brush size never rescales or loses existing strokes.
        let original = PKDrawing(strokes: [makeStroke(.pen, x: 240, y: 300)])
        canvas.drawing = original
        store.zoomTo(2)
        XCTAssertEqual(canvas.drawing.dataRepresentation(), original.dataRepresentation())
        window.isHidden = true
    }

    func testMarkerPenPencilAndEraserNibScreenSizeAtZoom() throws {
        let store = CanvasStore()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let canvas = PKCanvasView(frame: window.bounds)
        canvas.minimumZoomScale = 0.045
        canvas.maximumZoomScale = 10
        canvas.contentSize = CGSize(width: 12000, height: 12000)
        window.addSubview(canvas)
        let overlay = UIView(frame: window.bounds)
        window.addSubview(overlay)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        store.attach(canvas)

        for tool in [CanvasTool.pen, .pencil, .marker, .eraser] {
            store.tool = tool
            if tool == .marker { store.fixedHighlighter = false }
            store.setSelectedScreenNibWidth(12)
            for zoom: CGFloat in [0.5, 1, 2] {
                store.zoomTo(zoom)
                XCTAssertEqual(store.selectedScreenNibWidth, 12, accuracy: 0.05)
                XCTAssertEqual(store.nominalToolWidth * store.zoom, 12, accuracy: 0.05)
                if tool != .eraser {
                    assertScreenWidthIsActuallyRepresented(
                        store, canvas: canvas, overlay: overlay, desired: 12)
                } else {
                    XCTAssertTrue(canvas.tool is PKEraserTool,
                                  "Existing native eraser remains intact")
                }
            }
        }
        window.isHidden = true
    }

    func testOversizePencilPreviewReflectsActualPressureAndSingleDabs() {
        // This tests real UIKit path geometry, not just the width label.
        // Screen-space previews must reflect the exact pressure model that
        // commitScreenWidthStroke writes into editable PKStrokePoints.
        let low = ScreenWidthInkSample(
            location: CGPoint(x: 150, y: 160), time: 0, force: 0.2,
            azimuth: 0, altitude: .pi / 2)
        let high = ScreenWidthInkSample(
            location: CGPoint(x: 300, y: 160), time: 0.03, force: 0.8,
            azimuth: 0, altitude: .pi / 2)
        let size: CGFloat = 127
        let lowWidth = ScreenWidthInkTouchView.forceAdjustedScreenWidth(size, force: 0.2)
        let highWidth = ScreenWidthInkTouchView.forceAdjustedScreenWidth(size, force: 0.8)
        XCTAssertEqual(lowWidth, 127 * 0.82, accuracy: 0.01)
        XCTAssertEqual(highWidth, 127 * 1.18, accuracy: 0.01)
        XCTAssertGreaterThan(highWidth, lowWidth)

        let single = ScreenWidthInkTouchView.livePressurePath(
            [low], selectedWidth: size)
        XCTAssertEqual(single.bounds.width, lowWidth, accuracy: 0.03,
                       "The first stationary Pencil touch must render a full dot")
        XCTAssertEqual(single.bounds.height, lowWidth, accuracy: 0.03)

        let sweep = ScreenWidthInkTouchView.livePressurePath(
            [low, high], selectedWidth: size)
        XCTAssertGreaterThanOrEqual(sweep.bounds.height, highWidth - 0.1,
                                    "Live pressure stroke must expand rather than staying flat")
        XCTAssertGreaterThan(sweep.bounds.width, 150,
                             "Sample-to-sample sweep should cover the entire moving stroke")
    }

    func testActualPencilKitRasterWidthAtDeepAndNormalZoom() throws {
        // Render the REAL PKDrawing using Apple's rasterizer, not merely the
        // stored PKStrokePoint nominal dimensions. Preserve both full-size
        // raster results as named XCTest attachments for independent review.
        let store = CanvasStore()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let canvas = PKCanvasView(frame: window.bounds)
        canvas.minimumZoomScale = 0.045
        canvas.maximumZoomScale = 10
        canvas.contentSize = CGSize(width: 12000, height: 12000)
        window.addSubview(canvas)
        let overlay = UIView(frame: window.bounds)
        window.addSubview(overlay)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        store.attach(canvas)
        store.tool = .pen
        store.inkColor = UIColor(red: 0.03, green: 0.36, blue: 0.39, alpha: 1)
        for zoom: CGFloat in [0.102, 1.0] {
            canvas.drawing = PKDrawing()
            store.zoomTo(zoom)
            store.setSelectedScreenNibWidth(127)
            let time = Date().timeIntervalSince1970
            store.commitScreenWidthStroke([
                ScreenWidthInkSample(location: CGPoint(x: 300, y: 325),
                    time: time, force: 0.5, azimuth: 0, altitude: .pi / 2),
                ScreenWidthInkSample(location: CGPoint(x: 440, y: 325),
                    time: time + 0.025, force: 0.5,
                    azimuth: 0, altitude: .pi / 2)
            ], from: overlay)
            let stroke = try XCTUnwrap(canvas.drawing.strokes.last)
            XCTAssertEqual(stroke.path.count, 2)
            let midpoint = CGPoint(
                x: (stroke.path[0].location.x + stroke.path[1].location.x) / 2,
                y: (stroke.path[0].location.y + stroke.path[1].location.y) / 2)
            let worldRect = CGRect(x: midpoint.x - 110 / zoom,
                                   y: midpoint.y - 110 / zoom,
                                   width: 220 / zoom, height: 220 / zoom)
            let raster = canvas.drawing.image(from: worldRect, scale: zoom)

            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let preview = UIGraphicsImageRenderer(
                size: CGSize(width: 220, height: 220), format: format
            ).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 220, height: 220))
                raster.draw(in: CGRect(x: 0, y: 0, width: 220, height: 220))
            }
            let screenshot = XCTAttachment(image: preview)
            screenshot.name = zoom < 0.2
                ? "Real-PencilKit-raster-127pt-zoom-10-percent"
                : "Real-PencilKit-raster-127pt-zoom-100-percent"
            screenshot.lifetime = .keepAlways
            add(screenshot)

            guard let cg = preview.cgImage,
                  let data = cg.dataProvider?.data,
                  let bytes = CFDataGetBytePtr(data) else {
                XCTFail("Real PKDrawing rasterizer returned no inspectable bytes")
                continue
            }
            // At the centre of the horizontal pen path, any non-white pixel
            // belongs to the actual rendered ink (not an interface mock).
            // The renderer is white-backed solely for deterministic sampling.
            let bpp = cg.bitsPerPixel / 8
            XCTAssertGreaterThanOrEqual(bpp, 3)
            let sampleX = cg.width / 2
            var colouredRows = 0
            for y in 0..<cg.height {
                let index = y * cg.bytesPerRow + sampleX * bpp
                let darkness = Int(bytes[index]) + Int(bytes[index + 1])
                               + Int(bytes[index + 2])
                if darkness < 730 { colouredRows += 1 }
            }
            print("ACTUAL_PENCILKIT_RASTER zoom=\(zoom) colouredRows=\(colouredRows) desired=127")
            XCTAssertGreaterThan(colouredRows, 20,
                                 "A hairline stroke is not an acceptable oversized nib")
            XCTAssertEqual(CGFloat(colouredRows), 127, accuracy: 15,
                           "Measured REAL PencilKit raster should match 127 screen pt")
        }
        window.isHidden = true
    }

    func testExtremeScreenWidthUsesEditablePressureSensitivePKStroke() throws {
        let store = CanvasStore()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let canvas = PKCanvasView(frame: window.bounds)
        canvas.minimumZoomScale = 0.045
        canvas.maximumZoomScale = 10
        canvas.contentSize = CGSize(width: 12000, height: 12000)
        window.addSubview(canvas)
        let overlay = UIView(frame: window.bounds)
        window.addSubview(overlay)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        store.attach(canvas)
        store.tool = .pen
        store.setSelectedScreenNibWidth(127)
        for zoom: CGFloat in [0.102, 0.5, 1, 2] {
            store.zoomTo(zoom)
            XCTAssertTrue(store.needsScreenWidthInkOverlay,
                          "Oversized nib must select the editable width renderer")
            let before = canvas.drawing.strokes.count
            let time = Date().timeIntervalSince1970
            store.commitScreenWidthStroke([
                ScreenWidthInkSample(location: CGPoint(x: 300, y: 300),
                    time: time, force: 0.2, azimuth: 0, altitude: .pi / 2),
                ScreenWidthInkSample(location: CGPoint(x: 420, y: 300),
                    time: time + 0.015, force: 0.8, azimuth: 0, altitude: .pi / 3)
            ], from: overlay)
            XCTAssertEqual(canvas.drawing.strokes.count, before + 1)
            let stroke = try XCTUnwrap(canvas.drawing.strokes.last)
            XCTAssertGreaterThan(stroke.path[1].size.width, stroke.path[0].size.width,
                                 "Force should modify effective nib width")
            XCTAssertEqual(stroke.path[0].size.width * zoom,
                           127 * (0.70 + 0.60 * 0.2), accuracy: 2)
            XCTAssertEqual(stroke.path[1].size.width * zoom,
                           127 * (0.70 + 0.60 * 0.8), accuracy: 2)
            XCTAssertGreaterThan(stroke.renderBounds.height * zoom, 20,
                                 "Saved PencilKit ink should have visible thickness")
        }
        window.isHidden = true
    }

    func testRestSafeInsertedLinkCanBeTrashedAndRecoveredWithoutDeletingInk() throws {
        let store = CanvasStore()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let canvas = PKCanvasView(frame: window.bounds)
        canvas.minimumZoomScale = 0.045
        canvas.maximumZoomScale = 10
        canvas.contentSize = CGSize(width: 12000, height: 12000)
        window.addSubview(canvas)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        store.attach(canvas)
        XCTAssertTrue(store.restSafe)

        canvas.drawing = PKDrawing(strokes: [makeStroke(.pen, x: 180, y: 190)])
        let original = canvas.drawing.dataRepresentation()
        store.addTextNote("https://example.com/course/reading")
        let note = try XCTUnwrap(store.activeTextNotes.last)
        XCTAssertTrue(note.body.contains("https://"))

        store.trashTextNote(note)
        XCTAssertFalse(store.activeTextNotes.contains(where: { $0.id == note.id }))
        XCTAssertTrue(store.discardedTextNotes.contains(where: { $0.id == note.id }))
        XCTAssertEqual(canvas.drawing.dataRepresentation(), original,
                       "Deleting an inserted link must not delete PencilKit ink")
        let backupURL = try XCTUnwrap(store.exportCompleteBackup())
        let backup = try JSONDecoder().decode(CompleteBackup.self,
                                              from: Data(contentsOf: backupURL))
        XCTAssertEqual(backup.index.textNotes?.first(where: { $0.id == note.id })?.isTrashed, true,
                       "The soft-deleted note should survive backup/restart")
        store.restoreTextNote(note)
        XCTAssertTrue(store.activeTextNotes.contains(where: { $0.id == note.id }))
        XCTAssertEqual(canvas.drawing.dataRepresentation(), original)
        window.isHidden = true
    }

    func testFingerPanningRemainsAvailableAfterRestSafeAndOverlayToolSwitches() {
        let store = CanvasStore()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let canvas = PKCanvasView(frame: window.bounds)
        canvas.minimumZoomScale = 0.045
        canvas.maximumZoomScale = 10
        canvas.contentSize = CGSize(width: 12000, height: 12000)
        window.addSubview(canvas)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        store.attach(canvas)

        XCTAssertTrue(canvas.isScrollEnabled)
        XCTAssertFalse(canvas.isDirectionalLockEnabled)
        XCTAssertTrue(canvas.panGestureRecognizer.isEnabled)
        store.restSafe = false
        store.restSafe = true
        XCTAssertTrue(canvas.panGestureRecognizer.isEnabled)
        XCTAssertFalse(canvas.isDirectionalLockEnabled)
        store.tool = .capture
        XCTAssertFalse(canvas.panGestureRecognizer.isEnabled,
                       "Lasso overlay temporarily owns finger navigation")
        store.tool = .marker
        store.fixedHighlighter = true
        XCTAssertFalse(canvas.panGestureRecognizer.isEnabled,
                       "Fixed marker overlay temporarily owns finger navigation")
        store.tool = .pen
        XCTAssertTrue(canvas.panGestureRecognizer.isEnabled,
                      "Switching back to normal pen restores native finger navigation")

        for overlay in [LassoTouchView(frame: window.bounds),
                        FixedNibTouchView(frame: window.bounds)] as [UIView] {
            let pan = try? XCTUnwrap(overlay.gestureRecognizers?.compactMap {
                $0 as? UIPanGestureRecognizer
            }.first)
            XCTAssertEqual(pan?.minimumNumberOfTouches, 1)
            XCTAssertEqual(pan?.maximumNumberOfTouches, 2,
                           "Two fingers must not cancel navigation over full-screen overlays")
        }
        window.isHidden = true
    }


    func testLassoMoveCommitsAtCorrectZoomThenCanBeSelectedAgain() throws {
        let store = CanvasStore()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let canvas = PKCanvasView(frame: window.bounds)
        canvas.minimumZoomScale = 0.045
        canvas.maximumZoomScale = 10
        canvas.contentSize = CGSize(width: 12000, height: 12000)
        window.addSubview(canvas)
        let overlay = UIView(frame: window.bounds)
        window.addSubview(overlay)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        store.attach(canvas)
        store.tool = .capture

        for zoom: CGFloat in [0.5, 1, 2] {
            canvas.drawing = PKDrawing(strokes: [makeStroke(.pen, x: 200, y: 200)])
            store.clearSelection()
            canvas.setZoomScale(zoom, animated: false)
            canvas.setContentOffset(.zero, animated: false)
            func outline(_ center: CGPoint) -> [CGPoint] {
                let a = CanvasGeometry.viewportPoint(
                    drawing: CGPoint(x: center.x - 46, y: center.y - 46),
                    offset: canvas.contentOffset, scale: canvas.zoomScale)
                let b = CanvasGeometry.viewportPoint(
                    drawing: CGPoint(x: center.x + 46, y: center.y + 46),
                    offset: canvas.contentOffset, scale: canvas.zoomScale)
                return [a, CGPoint(x: b.x, y: a.y), b, CGPoint(x: a.x, y: b.y)]
            }

            store.captureLasso(outline(CGPoint(x: 200, y: 200)), from: overlay)
            XCTAssertTrue(store.selectionActive, "Should capture original stroke at zoom \(zoom)")
            let before = try XCTUnwrap(canvas.drawing.strokes.first).renderBounds
            let preview = try XCTUnwrap(store.beginSelectionDrag(in: overlay))
            XCTAssertEqual(preview.1.midX,
                           before.midX * zoom - canvas.contentOffset.x,
                           accuracy: 15, "Live preview must share the lasso coordinate system")
            store.finishSelectionDrag(screenDelta: CGSize(width: 120, height: 60))
            XCTAssertTrue(store.selectionActive,
                          "Selection must follow moved strokes, not disappear after lift")
            XCTAssertEqual(canvas.drawing.strokes.count, 1,
                           "Moving must not duplicate or leave source ink behind")
            let moved = try XCTUnwrap(canvas.drawing.strokes.first).renderBounds
            XCTAssertEqual(moved.midX - before.midX, 120 / zoom, accuracy: 2)
            XCTAssertEqual(moved.midY - before.midY, 60 / zoom, accuracy: 2)

            // Keep and move this SAME selected object again without requiring
            // a second lasso. Subsequent stash must still find its clip.
            let secondPreview = store.beginSelectionDrag(in: overlay)
            XCTAssertNotNil(secondPreview)
            store.cancelSelectionDrag()
            XCTAssertEqual(canvas.drawing.strokes.count, 1)
            XCTAssertTrue(store.selectionActive)
            XCTAssertTrue(store.stashSelectedInk(),
                          "Moved selection must still be stasheable without a new lasso")
            XCTAssertEqual(canvas.drawing.strokes.count, 1,
                           "Stashing moved ink must not delete the drawing")
            XCTAssertFalse(store.selectionActive)
            store.captureLasso(outline(CGPoint(x: moved.midX, y: moved.midY)), from: overlay)
            XCTAssertTrue(store.selectionActive,
                          "Moved handwriting must be selectable at its NEW location")
            XCTAssertEqual(store.latestClip?.strokeCount, 1)
            store.clearSelection()
        }
        window.isHidden = true
    }

    func testPencilOnlyCanvasOneFingerScrollAndNativeZoomLimit() {
        let store = CanvasStore()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let canvas = PKCanvasView(frame: window.bounds)
        canvas.minimumZoomScale = 0.045
        canvas.maximumZoomScale = 10
        // Use a moderate canvas for zoom API verification; 100k world performance
        // is a separate stress test and should not hold the whole release gate.
        canvas.contentSize = CGSize(width: 12000, height: 12000)
        window.addSubview(canvas)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        store.attach(canvas)

        XCTAssertEqual(canvas.drawingPolicy, .pencilOnly)
        XCTAssertTrue(canvas.isScrollEnabled, "One-finger scrolling must not be disabled by RestSafe")
        XCTAssertTrue(canvas.panGestureRecognizer.isEnabled)
        XCTAssertEqual(canvas.panGestureRecognizer.minimumNumberOfTouches, 1)
        XCTAssertTrue(canvas.pinchGestureRecognizer?.isEnabled == true)

        store.zoomTo(10)
        XCTAssertEqual(canvas.zoomScale, 10, accuracy: 0.01, "PencilKit must reach its native 1000% maximum")
        store.zoomTo(24)
        XCTAssertEqual(canvas.zoomScale, 10, accuracy: 0.01, "Native PencilKit zoom must safely clamp at 1000%")
        store.tool = .capture
        XCTAssertFalse(canvas.panGestureRecognizer.isEnabled, "Lasso overlay owns finger navigation")
        XCTAssertFalse(canvas.pinchGestureRecognizer?.isEnabled ?? true, "Lasso overlay owns pinch zoom")
        store.tool = .pen
        if store.needsScreenWidthInkOverlay {
            // At 1000% even a modest 2.5 screen-pt pen may be below the
            // native PKInkingTool minimum. The full-screen custom Pencil
            // view intentionally owns navigation; expecting the *covered*
            // native recognizers to be enabled is incorrect.
            XCTAssertFalse(canvas.panGestureRecognizer.isEnabled)
            XCTAssertFalse(canvas.pinchGestureRecognizer?.isEnabled ?? true)
            let overlay = ScreenWidthInkTouchView(frame: window.bounds)
            let pan = overlay.gestureRecognizers?
                .compactMap { $0 as? UIPanGestureRecognizer }.first
            let pinch = overlay.gestureRecognizers?
                .compactMap { $0 as? UIPinchGestureRecognizer }.first
            XCTAssertNotNil(pan, "Custom nib path must also provide finger navigation")
            XCTAssertNotNil(pinch, "Custom nib path must also provide pinch zoom")
            XCTAssertEqual(pan?.minimumNumberOfTouches, 1)
            XCTAssertEqual(pan?.maximumNumberOfTouches, 2)
        } else {
            XCTAssertTrue(canvas.panGestureRecognizer.isEnabled)
            XCTAssertTrue(canvas.pinchGestureRecognizer?.isEnabled ?? false)
        }
    }

    func testActualRootViewLaunchesWithVisibleControlsAndCanvas() async throws {
        // Apple Liquid Glass is drawn by the system compositor; CALayer.render
        // produces a blank snapshot for glass-backed SwiftUI controls.
        // Capture the same LIVE view/layout with a test-only solid material;
        // Xcode 27 compiles the native shipping-glass branch separately.
        setenv("INFINI_CANVAS_CI_SNAPSHOT", "1", 1)
        defer { unsetenv("INFINI_CANVAS_CI_SNAPSHOT") }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ??
                     UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        print("APP_TEST sceneAttached=\(window.windowScene != nil)")
        let host = UIHostingController(rootView: InfiniCanvasRootView())
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds

        // Allow SwiftUI and UIViewRepresentable to perform their real initial layout.
        try await Task.sleep(for: .milliseconds(600))
        window.layoutIfNeeded()
        host.view.layoutIfNeeded()
        XCTAssertFalse(host.view.isHidden)
        XCTAssertGreaterThan(host.view.bounds.width, 600)
        XCTAssertGreaterThan(host.view.bounds.height, 400)

        func collectCanvas(_ view: UIView) -> [PKCanvasView] {
            (view as? PKCanvasView).map { [$0] } ?? view.subviews.flatMap { collectCanvas($0) }
        }
        let canvases = collectCanvas(host.view)
        XCTAssertEqual(canvases.count, 1, "The root app must create the actual single native drawing surface")
        guard let canvas = canvases.first else { return }
        XCTAssertGreaterThan(canvas.bounds.width, 600)
        XCTAssertGreaterThan(canvas.bounds.height, 400)
        print("APP_TEST hostFrame=\(host.view.frame) canvasFrame=\(canvas.frame)")
        XCTAssertEqual(canvas.drawingPolicy, .pencilOnly)
        XCTAssertTrue(canvas.isScrollEnabled)

        // A fully white root screen hides even the normally visible command bar.
        // Sample a small thumbnail to catch blank-host regressions.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 0.25
        let renderer = UIGraphicsImageRenderer(size: window.bounds.size, format: format)
        let snapshot = renderer.image { context in
            // drawHierarchy returns false in SwiftPM's headless test runner
            // even when the scene and canvas are laid out. Render the layer
            // tree instead, then explicitly inspect the pixels.
            context.cgContext.scaleBy(x: 1, y: 1)
            window.layer.render(in: context.cgContext)
        }
        guard let cgImage = snapshot.cgImage, let data = cgImage.dataProvider?.data else {
            XCTFail("App root did not produce a screenshot"); return
        }
        let bytes = CFDataGetBytePtr(data)!
        let bytesPerPixel = max(1, cgImage.bitsPerPixel / 8)
        let bpr = cgImage.bytesPerRow
        let count = min(cgImage.height, 45)
        var colors = Set<String>()
        for y in 0..<count {
            for x in stride(from: 0, to: cgImage.width, by: 7) {
                let k = y * bpr + x * bytesPerPixel
                if bytesPerPixel >= 3 {
                    colors.insert("\(bytes[k]) \(bytes[k+1]) \(bytes[k+2])")
                }
            }
        }
        print("APP_TEST topPixelsDistinctColors=\(colors.count)")
        // Emit a very small thumbnail only for launch regression diagnosis.
        let thumb = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 120)).image { _ in
            snapshot.draw(in: CGRect(x: 0, y: 0, width: 160, height: 120))
        }
        if let data = thumb.pngData() {
            print("APP_TEST_IMAGE_BASE64:" + data.base64EncodedString())
        }
        XCTAssertGreaterThan(colors.count, 4, "Full app root must draw visible toolbar content in its top region")
        window.isHidden = true
    }

}
