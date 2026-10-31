import CoreGraphics

// Pure viewport/drawing transforms used by pinch, lasso, highlighter and area labels.
// No UIKit assumptions here: viewport coordinates are measured from the visible
// top-left corner, and offset is the UIScrollView contentOffset in zoomed points.
enum CanvasGeometry {
    static func drawingPoint(viewport: CGPoint, offset: CGPoint, scale: CGFloat) -> CGPoint {
        let z = max(scale, 0.0001)
        return CGPoint(x: (offset.x + viewport.x) / z,
                       y: (offset.y + viewport.y) / z)
    }

    static func viewportPoint(drawing: CGPoint, offset: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: drawing.x * scale - offset.x,
                y: drawing.y * scale - offset.y)
    }

    static func offsetPreservingAnchor(
        originalOffset: CGPoint,
        originalZoom: CGFloat,
        targetZoom: CGFloat,
        viewportAnchor: CGPoint
    ) -> CGPoint {
        let anchor = drawingPoint(viewport: viewportAnchor, offset: originalOffset, scale: originalZoom)
        return CGPoint(x: anchor.x * targetZoom - viewportAnchor.x,
                       y: anchor.y * targetZoom - viewportAnchor.y)
    }
}
