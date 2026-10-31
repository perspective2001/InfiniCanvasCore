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
    // A moved PKStroke may cross a lasso without containing its centre or any
    // sparsely sampled point. Detect the *segments* that cross the lasso edges.
    // Pure geometry: independent of UIKit touch recognition and PencilKit.
    static func segmentCrossesPolygon(_ a: CGPoint, _ b: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        for index in polygon.indices {
            let c = polygon[index]
            let d = polygon[(index + 1) % polygon.count]
            if lineSegmentsIntersect(a, b, c, d) { return true }
        }
        return false
    }

    private static func lineSegmentsIntersect(_ a: CGPoint, _ b: CGPoint,
                                              _ c: CGPoint, _ d: CGPoint) -> Bool {
        func cross(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        let p = cross(a, b, c)
        let q = cross(a, b, d)
        let r = cross(c, d, a)
        let s = cross(c, d, b)
        let eps: CGFloat = 0.00001
        func inside(_ x: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> Bool {
            x >= min(lo, hi) - eps && x <= max(lo, hi) + eps
        }
        if abs(p) <= eps && inside(c.x, a.x, b.x) && inside(c.y, a.y, b.y) { return true }
        if abs(q) <= eps && inside(d.x, a.x, b.x) && inside(d.y, a.y, b.y) { return true }
        if abs(r) <= eps && inside(a.x, c.x, d.x) && inside(a.y, c.y, d.y) { return true }
        if abs(s) <= eps && inside(b.x, c.x, d.x) && inside(b.y, c.y, d.y) { return true }
        return (p > 0) != (q > 0) && (r > 0) != (s > 0)
    }

}
