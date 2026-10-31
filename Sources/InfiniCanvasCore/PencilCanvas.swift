import SwiftUI
import UIKit
import PencilKit

// Only one PKCanvasView. Never overwrite drawing in updateUIView during a pen stroke.
struct PencilCanvas: UIViewRepresentable {
    @ObservedObject var store: CanvasStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView(frame: .zero)
        view.backgroundColor = CanvasStore.paperBackground(store.paper)
        view.isOpaque = true
        view.drawingPolicy = .pencilOnly
        view.isScrollEnabled = !store.restSafe
        // Wide but finite range: 0.045x–24x. Real unbounded zoom needs tiled ink architecture.
        view.minimumZoomScale = 0.045
        view.maximumZoomScale = 24
        view.bouncesZoom = false
        view.contentSize = CGSize(width: 100000, height: 100000)
        view.alwaysBounceVertical = false
        view.alwaysBounceHorizontal = false
        view.delegate = context.coordinator
        view.panGestureRecognizer.minimumNumberOfTouches = 2
        let deliberatePinch = UIPinchGestureRecognizer(target: context.coordinator,
                                                     action: #selector(Coordinator.handleDeliberatePinch(_:)))
        deliberatePinch.delegate = context.coordinator
        deliberatePinch.cancelsTouchesInView = false
        view.addGestureRecognizer(deliberatePinch)
        // System pencil gesture; switch quickly between last writing tool and eraser.
        // PencilKit handles Pencil drawing independently of UIPencilInteraction.
        // The optional Pencil double-tap/squeeze interaction is disabled until
        // we can test its SDK availability in Swift Playgrounds on-device.
        store.attach(view)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak store] in
            store?.restoreViewPosition()
        }
        return view
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Important: no drawing assignment here; otherwise ongoing strokes may vanish.
        if uiView.delegate == nil { uiView.delegate = context.coordinator }
        if uiView.isScrollEnabled == store.restSafe { store.applyPalmProtection() }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        private weak var store: CanvasStore?
        init(store: CanvasStore) { self.store = store }

        @objc func handleDeliberatePinch(_ recognizer: UIPinchGestureRecognizer) {
            // UI updates are serialized on the main actor.
            Task { @MainActor [weak store] in
                guard let store, store.restSafe, let host = recognizer.view else { return }
                store.handleFingerPinch(recognizer, in: host)
            }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            touch.type == .direct
        }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if store?.isProgrammaticDrawingUpdate == true { return }
            Task { @MainActor [weak store] in store?.drawingChanged() }
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            DispatchQueue.main.async { [weak store] in store?.refreshViewport() }
        }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            DispatchQueue.main.async { [weak store] in store?.refreshViewport() }
        }

    }
}

struct LassoOverlay: UIViewRepresentable {
    @ObservedObject var store: CanvasStore
    func makeUIView(context: Context) -> LassoTouchView {
        let view = LassoTouchView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.onComplete = { [weak store] points, overlay in store?.captureLasso(points, from: overlay) }
        view.onBeginMove = { [weak store] in store?.beginSelectionDrag() }
        view.onFinishMove = { [weak store] delta in store?.finishSelectionDrag(screenDelta: delta) }
        view.onCancelMove = { [weak store] in store?.cancelSelectionDrag() }
        view.onPinch = { [weak store] recognizer, overlay in store?.handleFingerPinch(recognizer, in: overlay) }
        view.onFingerPan = { [weak store] recognizer, overlay in store?.handleLassoPan(recognizer, in: overlay) }
        return view
    }
    func updateUIView(_ view: LassoTouchView, context: Context) {
        if !store.selectionActive && view.hasOutline { view.resetOutline() }
    }
}

final class LassoTouchView: UIView, UIGestureRecognizerDelegate {
    var onComplete: (([CGPoint], UIView) -> Void)?
    var onBeginMove: (() -> (UIImage, CGRect)?)?
    var onFinishMove: ((CGSize) -> Void)?
    var onCancelMove: (() -> Void)?
    var onPinch: ((UIPinchGestureRecognizer, UIView) -> Void)?
    var onFingerPan: ((UIPanGestureRecognizer, UIView) -> Void)?
    var hasOutline = false
    private var points: [CGPoint] = []
    private var beginning = CGPoint.zero
    private var lastPoint = CGPoint.zero
    private var moving = false
    private var selectedPreview: UIImageView?

    private let outline: CAShapeLayer = {
        let line = CAShapeLayer()
        line.fillColor = UIColor.systemTeal.withAlphaComponent(0.06).cgColor
        line.strokeColor = UIColor(red: 0.02, green: 0.49, blue: 0.54, alpha: 1).cgColor
        line.lineWidth = 2.0
        line.lineDashPattern = [6, 4]
        line.lineJoin = .round
        return line
    }()
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(outline)
        isMultipleTouchEnabled = true
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        pinch.cancelsTouchesInView = false
        addGestureRecognizer(pinch)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleFingerPan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
        accessibilityLabel = "Lasso handwriting. Pencil moves selected ink live; two-finger gestures navigate."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.type == .direct
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
    @objc private func handleFingerPan(_ recognizer: UIPanGestureRecognizer) {
        onFingerPan?(recognizer, self)
    }
    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        if recognizer.state == .changed && hasOutline && !moving {
            resetOutline()
        }
        onPinch?(recognizer, self)
    }
    private func path() -> UIBezierPath {
        let bezier = UIBezierPath()
        if let first = points.first {
            bezier.move(to: first)
            for point in points.dropFirst() { bezier.addLine(to: point) }
            if hasOutline { bezier.close() }
        }
        return bezier
    }
    private func redraw() {
        outline.path = path().cgPath
        outline.fillColor = hasOutline ? UIColor.systemTeal.withAlphaComponent(0.06).cgColor : UIColor.clear.cgColor
    }
    func resetOutline() {
        if moving { onCancelMove?() }
        selectedPreview?.removeFromSuperview()
        selectedPreview = nil
        points = []; hasOutline = false; moving = false; redraw()
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first(where: { $0.type == .pencil })?.location(in: self) else { return }
        beginning = location; lastPoint = location
        if hasOutline && path().contains(location), let (snapshot, rect) = onBeginMove?() {
            moving = true
            let preview = UIImageView(image: snapshot)
            preview.frame = rect
            preview.contentMode = .scaleToFill
            preview.isUserInteractionEnabled = false
            addSubview(preview)
            selectedPreview = preview
        } else {
            moving = false
            hasOutline = false
            points = [location]
            redraw()
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first(where: { $0.type == .pencil })?.location(in: self) else { return }
        if moving {
            let dx = location.x - beginning.x
            let dy = location.y - beginning.y
            // Cached PNG moves with the Pencil; vector ink is committed only once at lift.
            selectedPreview?.transform = CGAffineTransform(translationX: dx, y: dy)
            let stepX = location.x - lastPoint.x, stepY = location.y - lastPoint.y
            points = points.map { CGPoint(x: $0.x + stepX, y: $0.y + stepY) }
        } else if hypot(location.x - lastPoint.x, location.y - lastPoint.y) > 2 {
            points.append(location)
        }
        lastPoint = location
        redraw()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.contains(where: { $0.type == .pencil }) else { return }
        if moving {
            onFinishMove?(CGSize(width: lastPoint.x - beginning.x, height: lastPoint.y - beginning.y))
            selectedPreview?.removeFromSuperview()
            selectedPreview = nil
            hasOutline = true
        } else if points.count >= 4 {
            hasOutline = true; redraw(); onComplete?(points, self)
        } else { resetOutline() }
        moving = false
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { resetOutline() }
}

struct SystemShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
