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
        XCTAssertTrue(canvas.panGestureRecognizer.isEnabled)
        XCTAssertTrue(canvas.pinchGestureRecognizer?.isEnabled ?? false)
    }

    func testActualRootViewLaunchesWithVisibleControlsAndCanvas() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
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
        XCTAssertEqual(canvas.drawingPolicy, .pencilOnly)
        XCTAssertTrue(canvas.isScrollEnabled)

        // A fully white root screen hides even the normally visible command bar.
        // Sample a small thumbnail to catch blank-host regressions.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 0.25
        let renderer = UIGraphicsImageRenderer(size: window.bounds.size, format: format)
        let snapshot = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        guard let cgImage = snapshot.cgImage, let data = cgImage.dataProvider?.data else {
            XCTFail("App root did not produce a screenshot"); return
        }
        let bytes = CFDataGetBytePtr(data)!
        let bytesPerPixel = max(1, cgImage.bitsPerPixel / 8)
        let bpr = cgImage.bytesPerRow
        let count = min(cgImage.height, 45)
        var varied = false
        for y in 0..<count where !varied {
            for x in stride(from: 0, to: cgImage.width, by: 7) {
                let k = y * bpr + x * bytesPerPixel
                if bytesPerPixel >= 3 {
                    let c0 = Int(bytes[k]); let c1 = Int(bytes[k+1]); let c2 = Int(bytes[k+2])
                    if max(c0,c1,c2) - min(c0,c1,c2) > 14 ||
                       (c0 < 160 && c1 < 160 && c2 < 160) {
                        varied = true; break
                    }
                }
            }
        }
        XCTAssertTrue(varied, "App upper controls appear blank/white in captured root screen")
        window.isHidden = true
    }

}
