import XCTest
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
    func testPencilOnlyCanvasOneFingerScrollAndFullZoomRange() {
        let store = CanvasStore()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let canvas = PKCanvasView(frame: window.bounds)
        canvas.minimumZoomScale = 0.045
        canvas.maximumZoomScale = 32
        canvas.contentSize = CGSize(width: 100000, height: 100000)
        window.addSubview(canvas)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        store.attach(canvas)

        XCTAssertEqual(canvas.drawingPolicy, .pencilOnly)
        XCTAssertTrue(canvas.isScrollEnabled, "One-finger scrolling must not be disabled by RestSafe")
        XCTAssertTrue(canvas.panGestureRecognizer.isEnabled)
        XCTAssertEqual(canvas.panGestureRecognizer.minimumNumberOfTouches, 1)
        XCTAssertTrue(canvas.pinchGestureRecognizer?.isEnabled == true)

        store.zoomTo(24)
        XCTAssertEqual(canvas.zoomScale, 24, accuracy: 0.01, "The 2400% preset should be reachable")
        store.zoomTo(32)
        XCTAssertEqual(canvas.zoomScale, 32, accuracy: 0.01, "The 3200% safety ceiling should be reachable")
        store.tool = .capture
        XCTAssertFalse(canvas.panGestureRecognizer.isEnabled, "Lasso overlay owns finger navigation")
        XCTAssertFalse(canvas.pinchGestureRecognizer?.isEnabled ?? true, "Lasso overlay owns pinch zoom")
        store.tool = .pen
        XCTAssertTrue(canvas.panGestureRecognizer.isEnabled)
        XCTAssertTrue(canvas.pinchGestureRecognizer?.isEnabled ?? false)
    }

}
