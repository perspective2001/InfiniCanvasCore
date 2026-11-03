import SwiftUI
import UIKit
import PencilKit

// Source samples are always in the overlay's SCREEN coordinates. A custom
// editable PKStroke is made ONLY if PencilKit has clamped the desired nib.
// Ordinary widths keep Apple's native low-latency handwriting pipeline.
struct ScreenWidthInkSample {
    let location: CGPoint
    let time: TimeInterval
    let force: CGFloat
    let azimuth: CGFloat
    let altitude: CGFloat
}

struct ScreenWidthInkOverlay: UIViewRepresentable {
    @ObservedObject var store: CanvasStore

    func makeUIView(context: Context) -> ScreenWidthInkTouchView {
        let view = ScreenWidthInkTouchView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.onStroke = { [weak store] samples, source in
            store?.commitScreenWidthStroke(samples, from: source)
        }
        view.onPinch = { [weak store] recognizer, source in
            store?.handleFingerPinch(recognizer, in: source)
        }
        view.onFingerPan = { [weak store] recognizer, source in
            store?.handleLassoPan(recognizer, in: source)
        }
        return view
    }

    func updateUIView(_ view: ScreenWidthInkTouchView, context: Context) {
        view.screenWidth = store.selectedScreenNibWidth
        view.inkColor = store.inkColor
        view.previewOpacity = store.tool == .marker ? 0.45 : 1
    }
}

// One owner for each gesture: Pencil samples ink, deliberate direct-finger
// touches navigate, exactly like the existing full-screen marker overlay.
final class ScreenWidthInkTouchView: UIView, UIGestureRecognizerDelegate {
    var onStroke: (([ScreenWidthInkSample], UIView) -> Void)?
    var onPinch: ((UIPinchGestureRecognizer, UIView) -> Void)?
    var onFingerPan: ((UIPanGestureRecognizer, UIView) -> Void)?
    var screenWidth: CGFloat = 2.5
    var inkColor: UIColor = .black
    var previewOpacity: CGFloat = 1

    private var samples: [ScreenWidthInkSample] = []
    // Freeze completed short path chunks. Redrawing an entire long Pencil
    // stroke from scratch on every coalesced touch is quadratic and causes
    // lag. Only the most recent ~32 samples remain a moving CAShapeLayer.
    private var previewChunks: [CAShapeLayer] = []
    private var activeChunkStart = 0
    private let previewChunkSize = 32

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        pinch.delegate = self
        pinch.cancelsTouchesInView = false
        addGestureRecognizer(pinch)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError("Storyboards are not used") }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.type == .direct && touch.majorRadius < 38
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        onPinch?(gesture, self)
    }
    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        onFingerPan?(gesture, self)
    }

    private func append(_ touch: UITouch) {
        guard touch.type == .pencil else { return }
        let pt = touch.location(in: self)
        if let last = samples.last,
           hypot(last.location.x - pt.x, last.location.y - pt.y) < 0.25 { return }
        let pressure = touch.maximumPossibleForce > 0
            ? min(1, max(0, touch.force / touch.maximumPossibleForce)) : 0.5
        samples.append(ScreenWidthInkSample(
            location: pt, time: touch.timestamp,
            force: pressure, azimuth: touch.azimuthAngle(in: self),
            altitude: touch.altitudeAngle))
    }

    // The live display and committed PKStroke use the SAME force-to-width
    // calculation. A constant-width CAShapeLayer line used to lie about the
    // thickness of a pressure-varying stroke while the Pencil was down.
    static func forceAdjustedScreenWidth(_ width: CGFloat, force: CGFloat) -> CGFloat {
        max(0.4, width * (0.70 + 0.60 * min(1, max(0, force))))
    }

    // Construct a variable-width swept stroke using a round dab at every
    // sample and a trapezoid joining adjacent samples. This renders the
    // actual pressure envelope while moving, including a one-point dot.
    // Control point placement remains in screen space, independent of zoom.
    static func livePressurePath(_ points: [ScreenWidthInkSample],
                                 selectedWidth: CGFloat) -> UIBezierPath {
        let outline = UIBezierPath()
        guard let first = points.first else { return outline }
        func radius(_ point: ScreenWidthInkSample) -> CGFloat {
            forceAdjustedScreenWidth(selectedWidth, force: point.force) / 2
        }
        func disk(_ center: CGPoint, _ r: CGFloat) {
            outline.append(UIBezierPath(ovalIn: CGRect(
                x: center.x - r, y: center.y - r,
                width: r * 2, height: r * 2)))
        }
        disk(first.location, radius(first))
        if points.count < 2 { return outline }
        for index in 1..<points.count {
            let old = points[index - 1]
            let next = points[index]
            let dx = next.location.x - old.location.x
            let dy = next.location.y - old.location.y
            let distance = hypot(dx, dy)
            let r1 = radius(old)
            let r2 = radius(next)
            guard distance >= 0.001 else {
                disk(next.location, r2)
                continue
            }
            let nx = -dy / distance
            let ny = dx / distance
            outline.move(to: CGPoint(x: old.location.x + nx * r1,
                                     y: old.location.y + ny * r1))
            outline.addLine(to: CGPoint(x: next.location.x + nx * r2,
                                        y: next.location.y + ny * r2))
            outline.addLine(to: CGPoint(x: next.location.x - nx * r2,
                                        y: next.location.y - ny * r2))
            outline.addLine(to: CGPoint(x: old.location.x - nx * r1,
                                        y: old.location.y - ny * r1))
            outline.close()
            disk(next.location, r2)
        }
        return outline
    }

    private func newPreviewChunk() -> CAShapeLayer {
        let chunk = CAShapeLayer()
        chunk.contentsScale = UIScreen.main.scale
        chunk.fillColor = inkColor.withAlphaComponent(previewOpacity).cgColor
        chunk.strokeColor = nil
        layer.addSublayer(chunk)
        previewChunks.append(chunk)
        return chunk
    }

    private func render() {
        guard !samples.isEmpty else { return }
        if previewChunks.isEmpty { _ = newPreviewChunk() }
        while samples.count - activeChunkStart > previewChunkSize {
            let end = activeChunkStart + previewChunkSize
            let finished = Array(samples[activeChunkStart..<end])
            previewChunks[previewChunks.count - 1].path =
                Self.livePressurePath(finished, selectedWidth: screenWidth).cgPath
            activeChunkStart = end - 1  // one shared sample prevents seams
            _ = newPreviewChunk()
        }
        let current = Array(samples[activeChunkStart...])
        previewChunks[previewChunks.count - 1].path =
            Self.livePressurePath(current, selectedWidth: screenWidth).cgPath
    }
    private func reset() {
        samples.removeAll(keepingCapacity: true)
        previewChunks.forEach { $0.removeFromSuperlayer() }
        previewChunks.removeAll(keepingCapacity: true)
        activeChunkStart = 0
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pencil = touches.first(where: { $0.type == .pencil }) else { return }
        reset()
        append(pencil)
        render()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pencil = touches.first(where: { $0.type == .pencil }) else { return }
        for point in event?.coalescedTouches(for: pencil) ?? [pencil] {
            append(point)
        }
        render()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pencil = touches.first(where: { $0.type == .pencil }) else { return }
        for point in event?.coalescedTouches(for: pencil) ?? [pencil] {
            append(point)
        }
        let finished = samples
        reset()
        if !finished.isEmpty { onStroke?(finished, self) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        reset()
    }
}
