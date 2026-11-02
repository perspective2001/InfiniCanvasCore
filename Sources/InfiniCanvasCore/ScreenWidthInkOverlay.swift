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
    private let liveLine = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        layer.addSublayer(liveLine)
        liveLine.fillColor = nil
        liveLine.lineJoin = .round
        liveLine.lineCap = .round
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

    private func render() {
        let path = UIBezierPath()
        for (index, sample) in samples.enumerated() {
            if index == 0 { path.move(to: sample.location) }
            else { path.addLine(to: sample.location) }
        }
        liveLine.path = path.cgPath
        liveLine.lineWidth = max(0.4, screenWidth)
        liveLine.strokeColor = inkColor.withAlphaComponent(previewOpacity).cgColor
    }
    private func reset() {
        samples.removeAll(keepingCapacity: true)
        liveLine.path = nil
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
