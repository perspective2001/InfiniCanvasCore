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
        // Native PencilKit draws only with Pencil; finger gestures navigate.
        // Apple documents one-finger scrolling in pencil-only mode.
        view.isScrollEnabled = true
        // The canvas fills the iPad: no scrollbar should appear when panning.
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.minimumZoomScale = 0.045
        view.maximumZoomScale = 10
        view.bouncesZoom = false
        view.contentSize = CGSize(width: 100000, height: 100000)
        view.alwaysBounceVertical = false
        view.alwaysBounceHorizontal = false
        view.delegate = context.coordinator
        view.panGestureRecognizer.minimumNumberOfTouches = 1
        // Use the system's OWN pan and pinch recognizers on the canvas.
        // Custom overlay recognizers are reserved for Lasso and fixed highlighter.
        // Do not attach a second competing UIPinchGestureRecognizer here.
        store.attach(view)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak store] in
            store?.restoreViewPosition()
        }
        return view
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Important: no drawing assignment here; otherwise ongoing strokes may vanish.
        if uiView.delegate == nil { uiView.delegate = context.coordinator }
        // Tool and drawing-policy changes are applied by CanvasStore. Avoid
        // resetting scroll recognizers on every SwiftUI state update.
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private weak var store: CanvasStore?
        init(store: CanvasStore) { self.store = store }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            // Keep ordering with synchronous layer and lasso drawing mutations.
            MainActor.assumeIsolated {
                guard let store, !store.isProgrammaticDrawingUpdate else { return }
                store.drawingChanged()
            }
        }
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            MainActor.assumeIsolated { store?.refreshViewport() }
        }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            MainActor.assumeIsolated { store?.refreshViewport() }
        }

    }
}

struct LassoOverlay: UIViewRepresentable {
    @ObservedObject var store: CanvasStore
    // Updated by a SwiftUI geometry preference from the compact toolbar stash well.
    var stashDropFrame: CGRect = .null
    var onStashProximity: (CGFloat) -> Void = { _ in }

    func makeUIView(context: Context) -> LassoTouchView {
        let view = LassoTouchView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.onComplete = { [weak store] points, overlay in store?.captureLasso(points, from: overlay) }
        view.onBeginMove = { [weak store, weak view] in
            guard let view else { return nil }
            return store?.beginSelectionDrag(in: view)
        }
        view.onFinishMove = { [weak store] delta in store?.finishSelectionDrag(screenDelta: delta) }
        view.onCancelMove = { [weak store] in store?.cancelSelectionDrag() }
        view.onPinch = { [weak store] recognizer, overlay in store?.handleFingerPinch(recognizer, in: overlay) }
        view.onFingerPan = { [weak store] recognizer, overlay in store?.handleLassoPan(recognizer, in: overlay) }
        view.stashDropFrame = stashDropFrame
        view.onStashDrop = { [weak store] in store?.stashSelectedInk() ?? false }
        view.onStashProximity = onStashProximity
        return view
    }
    func updateUIView(_ view: LassoTouchView, context: Context) {
        view.stashDropFrame = stashDropFrame
        view.onStashProximity = onStashProximity
        if !store.selectionActive && view.hasOutline && !view.isDragging { view.resetOutline() }
    }
}

final class LassoTouchView: UIView, UIGestureRecognizerDelegate {
    var onComplete: (([CGPoint], UIView) -> Void)?
    var onBeginMove: (() -> (UIImage, CGRect)?)?
    var onFinishMove: ((CGSize) -> Void)?
    var onCancelMove: (() -> Void)?
    var onStashDrop: (() -> Bool)?
    var onStashProximity: ((CGFloat) -> Void)?
    var stashDropFrame: CGRect = .null
    var onPinch: ((UIPinchGestureRecognizer, UIView) -> Void)?
    var onFingerPan: ((UIPanGestureRecognizer, UIView) -> Void)?
    var hasOutline = false
    private var points: [CGPoint] = []
    private var beginning = CGPoint.zero
    private var lastPoint = CGPoint.zero
    private var moving = false
    var isDragging: Bool { moving }
    private var selectedPreview: UIImageView?
    private var dragPreviewInitialFrame: CGRect = .zero
    private var wasNearStash = false

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
        pan.minimumNumberOfTouches = 1
        // Let deliberate two-finger translation continue when an extra finger
        // touches the screen. The pinch handler takes precedence while scaling.
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
        accessibilityLabel = "Pencil lasso. Move selections with Pencil; one finger pans, two fingers zoom."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Filter broad stationary palm contacts from custom overlay navigation.
        // iPad direct finger radius fluctuates with contact angle. The older
        // 27pt cutoff rejected legitimate broad finger touches, leaving the
        // full-screen ink overlay unable to pan horizontally at all.
        // Keep a finite cutoff to ignore large palm contacts.
        touch.type == .direct && touch.majorRadius < 38
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
        dragPreviewInitialFrame = .zero
        wasNearStash = false
        onStashProximity?(0)
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
            dragPreviewInitialFrame = rect
        } else {
            moving = false
            hasOutline = false
            points = [location]
            redraw()
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pencil = touches.first(where: { $0.type == .pencil }) else { return }
        if moving {
            let location = pencil.location(in: self)
            let dx = location.x - beginning.x
            let dy = location.y - beginning.y
            // Live drag-to-tray preview. Shrink only as the OUTER EDGE of the
            // moving selection approaches the receiving strip, not only when
            // the stylus tip enters it. Pencil position remains the source of
            // truth; nothing is saved until the final intentional drop.
            let movedRect = dragPreviewInitialFrame.offsetBy(dx: dx, dy: dy)
            let proximity = Self.proximity(of: movedRect, to: stashDropFrame)
            if proximity > 0.01 && !wasNearStash {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.40)
            }
            wasNearStash = proximity > 0.01
            onStashProximity?(proximity)
            if let preview = selectedPreview {
                preview.transform = CGAffineTransform(scaleX: max(0.13, 1 - proximity * 0.87),
                                                      y: max(0.13, 1 - proximity * 0.87))
                let originalCenter = CGPoint(x: dragPreviewInitialFrame.midX + dx,
                                             y: dragPreviewInitialFrame.midY + dy)
                let pull = proximity * 0.28
                preview.center = CGPoint(
                    x: originalCenter.x + (stashDropFrame.midX - originalCenter.x) * pull,
                    y: originalCenter.y + (stashDropFrame.midY - originalCenter.y) * pull)
                preview.alpha = 1 - proximity * 0.08
            }
            let stepX = location.x - lastPoint.x
            let stepY = location.y - lastPoint.y
            points = points.map { CGPoint(x: $0.x + stepX, y: $0.y + stepY) }
            lastPoint = location
        } else {
            // Preserve coalesced Pencil points at speed, rather than sampling one
            // position per display frame and accidentally cutting lasso corners.
            for sample in event?.coalescedTouches(for: pencil) ?? [pencil] {
                let location = sample.location(in: self)
                if hypot(location.x - lastPoint.x, location.y - lastPoint.y) > 1.25 {
                    points.append(location)
                    lastPoint = location
                }
            }
        }
        redraw()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pencil = touches.first(where: { $0.type == .pencil }) else { return }
        let ending = pencil.location(in: self)
        if moving {
            // The source drawing is restored before stashing: the UI does not
            // delete the handwriting, it saves a compact reference to the clip.
            // stashDropFrame and LassoTouchView are both in the root drawing
            // view coordinate system. The previous code compared SwiftUI's
            // frame to UIWindow coordinates, which can differ by safe-area
            // and hosting view offsets.
            let movedRect = dragPreviewInitialFrame.offsetBy(
                dx: ending.x - beginning.x, dy: ending.y - beginning.y)
            let touchesStash = stashDropFrame != .null &&
                (stashDropFrame.insetBy(dx: -13, dy: -11).contains(ending) ||
                 movedRect.intersects(stashDropFrame.insetBy(dx: -8, dy: -8)))
            if touchesStash, onStashDrop?() == true {
                moving = false
                hasOutline = false
                points = []
                redraw()
                onStashProximity?(0)
                let thumbnail = selectedPreview
                selectedPreview = nil
                let target = CGPoint(x: stashDropFrame.midX, y: stashDropFrame.midY)
                if let thumbnail {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    UIView.animate(withDuration: 0.38, delay: 0,
                                   usingSpringWithDamping: 0.77, initialSpringVelocity: 0.32,
                                   options: [.curveEaseInOut, .allowUserInteraction]) {
                        thumbnail.center = target
                        thumbnail.transform = CGAffineTransform(scaleX: 0.09, y: 0.09)
                        thumbnail.alpha = 0
                    } completion: { _ in thumbnail.removeFromSuperview() }
                }
                return
            }

            // Include the Pencil's final travel since the last moved event.
            let stepX = ending.x - lastPoint.x
            let stepY = ending.y - lastPoint.y
            points = points.map { CGPoint(x: $0.x + stepX, y: $0.y + stepY) }
            onFinishMove?(CGSize(width: ending.x - beginning.x, height: ending.y - beginning.y))
            selectedPreview?.removeFromSuperview()
            selectedPreview = nil
            // The outline has already moved with the Pencil each frame.
            // Keep it attached to the *new* stroke location after lift so
            // another drag can start immediately, including a toolbar drop.
            hasOutline = true
            onStashProximity?(0)
            redraw()
        } else {
            if hypot(ending.x - lastPoint.x, ending.y - lastPoint.y) > 1.25 {
                points.append(ending)
            }
            if points.count >= 4 {
                hasOutline = true; redraw(); onComplete?(points, self)
            } else { resetOutline() }
        }
        moving = false
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { resetOutline() }

    // Pure geometry helper, regression-tested for corner contact with tray.
    static func proximity(of rect: CGRect, to target: CGRect) -> CGFloat {
        guard !target.isNull, !target.isEmpty, !rect.isEmpty else { return 0 }
        let horizontal = max(0, target.minX - rect.maxX, rect.minX - target.maxX)
        let vertical = max(0, target.minY - rect.maxY, rect.minY - target.maxY)
        let distance = hypot(horizontal, vertical)
        return max(0, min(1, 1 - distance / 120))
    }
}

struct SystemShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
