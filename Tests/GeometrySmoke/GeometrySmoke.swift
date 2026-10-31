import Foundation
import CoreGraphics

@main
struct GeometryRegressionTests {
    static func near(_ a: CGFloat, _ b: CGFloat, _ description: String) {
        let tolerance: CGFloat = max(0.00001, abs(b) * 0.0000001)
        precondition(abs(a - b) <= tolerance, "\(description): \(a) vs \(b)")
    }
    static func main() {
        let scales: [CGFloat] = [0.045, 0.14, 0.25, 0.75, 1, 2, 4, 12, 24]
        let offsets: [CGPoint] = [
            .zero, CGPoint(x: 8034.5, y: 1211.3),
            CGPoint(x: 490000, y: 277000)
        ]
        let points: [CGPoint] = [
            .zero, CGPoint(x: 128, y: 90),
            CGPoint(x: 530, y: 410),
            CGPoint(x: 1110, y: 810)
        ]
        var checks = 0
        for oldScale in scales {
            for offset in offsets {
                for viewport in points {
                    let world = CanvasGeometry.drawingPoint(viewport: viewport, offset: offset, scale: oldScale)
                    let roundtrip = CanvasGeometry.viewportPoint(drawing: world, offset: offset, scale: oldScale)
                    near(roundtrip.x, viewport.x, "round-trip x")
                    near(roundtrip.y, viewport.y, "round-trip y")
                    checks += 2
                    for newScale in scales {
                        let newOffset = CanvasGeometry.offsetPreservingAnchor(
                            originalOffset: offset,
                            originalZoom: oldScale,
                            targetZoom: newScale,
                            viewportAnchor: viewport
                        )
                        let after = CanvasGeometry.drawingPoint(viewport: viewport, offset: newOffset, scale: newScale)
                        near(after.x, world.x, "anchored pinch x")
                        near(after.y, world.y, "anchored pinch y")
                        checks += 2
                    }
                }
            }
        }
        // A long moved stroke can cross a lasso even when both end points
        // and the stroke centre lie outside the capture polygon.
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0),
                      CGPoint(x: 20, y: 20), CGPoint(x: 0, y: 20)]
        precondition(CanvasGeometry.segmentCrossesPolygon(CGPoint(x: -10, y: 10),
                         CGPoint(x: 30, y: 10), polygon: square),
                     "lasso must catch long strokes crossing the interior")
        precondition(CanvasGeometry.segmentCrossesPolygon(CGPoint(x: 0, y: 10),
                         CGPoint(x: 30, y: 10), polygon: square),
                     "lasso must catch a stroke touching the border")
        precondition(!CanvasGeometry.segmentCrossesPolygon(CGPoint(x: 40, y: 10),
                         CGPoint(x: 50, y: 10), polygon: square),
                     "lasso must not select a nonintersecting distant stroke")
        checks += 3
        print("PASS: \(checks) geometry checks across 4.5%–2400% mathematical zoom, multiple offsets and touch positions")
    }
}
