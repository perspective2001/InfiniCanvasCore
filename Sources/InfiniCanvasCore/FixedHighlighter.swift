import SwiftUI
import UIKit
import PencilKit

// A dedicated fixed-nib Pencil overlay. It never captures fingers for drawing.
// Live tip is a vertical rectangle; at Pencil lift an editable PKStroke is committed.
struct FixedHighlighterOverlay: UIViewRepresentable {
    @ObservedObject var store: CanvasStore

    func makeUIView(context: Context) -> FixedNibTouchView {
        let view = FixedNibTouchView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.onStroke = { [weak store] samples, host in
            store?.commitFixedMarker(samples, in: host)
        }
        view.onPinch = { [weak store] pinch, host in
            store?.handleFingerPinch(pinch, in: host)
        }
        view.onFingerPan = { [weak store] pan, host in
            store?.handleLassoPan(pan, in: host)
        }
        return view
    }
    func updateUIView(_ view: FixedNibTouchView, context: Context) {
        view.nibHeight = store.markerHeight * max(0.045, store.zoom)
        view.nibWidth = store.markerWidth * max(0.045, store.zoom)
        view.tint = store.inkColor
    }
}

final class FixedNibTouchView: UIView, UIGestureRecognizerDelegate {
    var onStroke: (([CGPoint], UIView) -> Void)?
    var onPinch: ((UIPinchGestureRecognizer, UIView) -> Void)?
    var onFingerPan: ((UIPanGestureRecognizer, UIView) -> Void)?
    var nibWidth: CGFloat = 5
    var nibHeight: CGFloat = 22
    var tint: UIColor = .systemYellow
    private var points: [CGPoint] = []

    private let inkPreview = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        layer.addSublayer(inkPreview)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        pinch.delegate = self
        pinch.cancelsTouchesInView = false
        addGestureRecognizer(pinch)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.minimumNumberOfTouches = 1
        // Support lateral navigation even when a second finger lands mid-pan;
        // the simultaneous pinch recognizer owns scale adjustments.
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
        accessibilityLabel = "Fixed vertical tip highlighter: Apple Pencil only"
    }
    required init?(coder: NSCoder) { fatalError("Storyboards are not used") }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // iPad direct finger radius fluctuates with contact angle. The older
        // 27pt cutoff rejected legitimate broad finger touches, leaving the
        // full-screen ink overlay unable to pan horizontally at all.
        // Keep a finite cutoff to ignore large palm contacts.
        touch.type == .direct && touch.majorRadius < 38
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        onPinch?(gesture, self)
    }
    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        onFingerPan?(gesture, self)
    }

    private func append(_ touch: UITouch) {
        let location = touch.location(in: self)
        if let last = points.last, hypot(location.x - last.x, location.y - last.y) < 0.8 { return }
        points.append(location)
    }
    private func renderPreview() {
        // Vertical rectangular nib stamped along the sampled path: the tip NEVER follows
        // the Pencil's rotation. This is an overdraw preview, not an image screenshot.
        let path = UIBezierPath()
        let width = max(1.5, nibWidth)
        let height = max(3, nibHeight)
        for (index, point) in points.enumerated() {
            if index == 0 {
                path.append(UIBezierPath(roundedRect: CGRect(x: point.x - width / 2,
                            y: point.y - height / 2, width: width, height: height), cornerRadius: 1))
            } else {
                let last = points[index - 1]
                let distance = hypot(point.x - last.x, point.y - last.y)
                let steps = max(1, Int(ceil(distance / max(1, width * 0.5))))
                for step in 1...steps {
                    let t = CGFloat(step) / CGFloat(steps)
                    let x = last.x + (point.x - last.x) * t
                    let y = last.y + (point.y - last.y) * t
                    path.append(UIBezierPath(rect: CGRect(x: x - width / 2,
                        y: y - height / 2, width: width, height: height)))
                }
            }
        }
        inkPreview.path = path.cgPath
        inkPreview.fillColor = tint.withAlphaComponent(0.35).cgColor
        inkPreview.strokeColor = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pencil = touches.first(where: { $0.type == .pencil }) else { return }
        points = []
        append(pencil)
        renderPreview()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pencil = touches.first(where: { $0.type == .pencil }) else { return }
        for touch in event?.coalescedTouches(for: pencil) ?? [pencil] { append(touch) }
        renderPreview()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pencil = touches.first(where: { $0.type == .pencil }) else { return }
        append(pencil)
        let captured = points
        points = []
        // Commit one stroke at lift; never commit partial in-progress marks.
        onStroke?(captured, self)
        inkPreview.path = nil
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        points = []
        inkPreview.path = nil
    }
}
