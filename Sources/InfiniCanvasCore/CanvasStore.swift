import SwiftUI
import UIKit
import PencilKit
import Vision
import AVFoundation

// Infini Canvas v0.4. A single native PKDrawing, with a separately saved spatial index.
// Existing 0.3 drawing/clip/index files remain readable; optional fields are additive.
enum CanvasTool: String, CaseIterable, Identifiable {
    case pen = "Pen", pencil = "Pencil", marker = "Highlighter", eraser = "Eraser", capture = "Lasso"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .pencil: return "pencil"
        case .marker: return "highlighter"
        case .eraser: return "eraser"
        case .capture: return "lasso"
        }
    }
}

enum PaperStyle: String, Codable, CaseIterable, Identifiable {
    case blank = "Blank", ruled = "Ruled", grid = "Graph", dots = "Dots"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .blank: return "square"
        case .ruled: return "line.3.horizontal"
        case .grid: return "square.grid.3x3"
        case .dots: return "circle.grid.3x3"
        }
    }
}

enum PenProfile: String, CaseIterable, Identifiable {
    case fluid = "Fluid", fountain = "Fountain", monoline = "Monoline"
    var id: String { rawValue }
}

enum EraserPrecision: String, CaseIterable, Identifiable {
    case detail = "Detail", stroke = "Whole stroke"
    var id: String { rawValue }
}

enum StudioMode: String, CaseIterable {
    case notes = "Notes", art = "Art"
}

enum ReviewRating: String, CaseIterable, Identifiable {
    case again = "Again", hard = "Hard", good = "Good", easy = "Easy"
    var id: String { rawValue }
}

struct SavedClip: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var imageName: String
    var strokeCount: Int
    var recognizedText: String? = nil
    var drawingName: String? = nil
    var course: String? = nil
    var isTrashed: Bool? = nil
    var isPinned: Bool? = nil
    var nextReview: Date? = nil
    var sourceX: Double? = nil
    var sourceY: Double? = nil
    var audioSessionID: UUID? = nil
    var audioSecond: Double? = nil
    var reviewIntervalDays: Int? = nil
    var reviewCount: Int? = nil
}

struct CanvasArea: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var x: Double
    var y: Double
    var isTrashed: Bool? = nil
    var width: Double? = nil
    var height: Double? = nil
    var isHidden: Bool? = nil
}

struct TypedNote: Codable, Identifiable, Equatable {
    var id: UUID
    var body: String
    var x: Double
    var y: Double
    var isTrashed: Bool? = nil
}

struct LectureMark: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var seconds: Double
    var x: Double
    var y: Double
    var clipID: UUID? = nil
}

struct LectureSession: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var audioFile: String
    var duration: Double
    var marks: [LectureMark]
}

struct CanvasIndex: Codable {
    var areas: [CanvasArea] = []
    var clips: [SavedClip] = []
    var paper: PaperStyle? = nil
    var indexVersion: Int? = nil
    var textNotes: [TypedNote]? = nil
    var lectureSessions: [LectureSession]? = nil
}

struct CompleteBackup: Codable {
    var format: String
    var exportedAt: Date
    var drawing: Data
    var index: CanvasIndex
    var clipImages: [String: Data]
    var clipDrawings: [String: Data]
    var audioFiles: [String: Data]? = nil
    // Optional for compatibility with older exports that predate Art Studio backups.
    var artworkData: Data? = nil
}

@MainActor
final class CanvasStore: ObservableObject {
    @Published var tool: CanvasTool = .pen {
        didSet {
            // Lasso selection belongs to the lasso overlay, not the next pen/eraser.
            if oldValue == .capture && tool != .capture { clearSelection() }
            updateTool()
        }
    }
    @Published var inkColor = UIColor(red: 0.10, green: 0.16, blue: 0.20, alpha: 1) { didSet { updateTool() } }
    @Published var strokeWidth: CGFloat = 2.5 { didSet { updateTool() } }
    @Published var penProfile: PenProfile = .fluid {
        didSet { UserDefaults.standard.set(penProfile.rawValue, forKey: "InfiniCanvas.penProfile"); updateTool() }
    }
    // Fixed nib is a dedicated Pencil-only renderer, not a claim that native PencilKit locks tilt.
    @Published var fixedHighlighter = true {
        didSet { UserDefaults.standard.set(fixedHighlighter, forKey: "InfiniCanvas.fixedHighlighter"); updateTool() }
    }
    @Published var markerHeight: CGFloat = 22 {
        didSet { UserDefaults.standard.set(Double(markerHeight), forKey: "InfiniCanvas.markerHeight") }
    }
    @Published var markerWidth: CGFloat = 5 {
        didSet { UserDefaults.standard.set(Double(markerWidth), forKey: "InfiniCanvas.markerWidth") }
    }
    @Published var paper: PaperStyle = .blank { didSet { canvas?.backgroundColor = Self.paperBackground(paper); saveIndex() } }
    @Published var clips: [SavedClip] = []
    @Published var areas: [CanvasArea] = []
    @Published var textNotes: [TypedNote] = []
    // Palm rest cannot pan the drawing. Unlock only when the user needs navigation.
    @Published var restSafe = true { didSet { applyPalmProtection() } }
    @Published var pencilShortcutsEnabled = false {
        didSet { UserDefaults.standard.set(pencilShortcutsEnabled, forKey: "InfiniCanvas.pencilShortcuts") }
    }
    @Published var lectureSessions: [LectureSession] = []
    @Published var recording = false
    @Published var recordingSeconds: Double = 0
    @Published var playingSessionID: UUID?
    @Published var organizationProposal: [UUID: String] = [:]
    @Published var organizedUndo: [UUID: String] = [:]
    @Published var organizationPreview = false
    @Published var latestClip: SavedClip?
    @Published var status = "Ready to write"
    @Published var selectionActive = false
    @Published var isSaved = true
    @Published var eraserPrecision: EraserPrecision = .detail { didSet { updateTool() } }
    @Published var eraserWidth: CGFloat = 12 { didSet { updateTool() } }
    @Published var mode: StudioMode = .notes { didSet { updateTool() } }
    @Published var focusAreaID: UUID? = nil
    @Published var zoom: CGFloat = 1
    @Published var offset: CGPoint = .zero

    private(set) var initialDrawing = PKDrawing()
    weak var canvas: PKCanvasView?
    private var selectedIndices: Set<Int> = []
    private var dragOriginal: PKDrawing?
    private var dragSelected: [PKStroke] = []
    private var dragRemaining: [PKStroke] = []
    private var dragBounds: CGRect = .zero
    private var pinchActivated = false
    private var pinchStartingZoom: CGFloat = 1
    private var pinchWorldAnchor: CGPoint = .zero
    private var panStartingOffset: CGPoint = .zero
    private var panStartingTranslation: CGPoint = .zero
    private var editUndo: [PKDrawing] = []
    private var editRedo: [PKDrawing] = []
    private var saveWork: DispatchWorkItem?
    private var toolPicker: PKToolPicker?
    private var recorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var currentRecordingID: UUID?
    private var currentRecordingName: String?
    private var recordingStartedAt: Date?
    private var rememberedTool: CanvasTool = .pen
    private var loading = false
    var isProgrammaticDrawingUpdate: Bool { loading }
    private var indexReady = false
    private var lastRevisionDate = Date.distantPast

    private let directory: URL
    private let clipsFolder: URL
    private let revisionsFolder: URL
    private let audioFolder: URL
    private let autosaveFolder: URL
    private let drawingFile: URL
    private let recoveryFile: URL
    private let indexFile: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = docs.appendingPathComponent("InfiniCanvas", isDirectory: true)
        clipsFolder = directory.appendingPathComponent("Clips", isDirectory: true)
        revisionsFolder = directory.appendingPathComponent("Revisions", isDirectory: true)
        audioFolder = directory.appendingPathComponent("Lectures", isDirectory: true)
        autosaveFolder = directory.appendingPathComponent("AutomaticBackups", isDirectory: true)
        drawingFile = directory.appendingPathComponent("canvas.pkdrawing")
        recoveryFile = directory.appendingPathComponent("canvas-recovery.pkdrawing")
        indexFile = directory.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: clipsFolder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: revisionsFolder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: audioFolder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: autosaveFolder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: drawingFile), let drawing = try? PKDrawing(data: data) {
            initialDrawing = drawing
        } else if let data = try? Data(contentsOf: recoveryFile), let drawing = try? PKDrawing(data: data) {
            initialDrawing = drawing
            status = "Recovered a previous drawing"
        }
        if let data = try? Data(contentsOf: indexFile), let model = try? JSONDecoder().decode(CanvasIndex.self, from: data) {
            clips = model.clips
            areas = model.areas
            textNotes = model.textNotes ?? []
            lectureSessions = model.lectureSessions ?? []
            paper = model.paper ?? .blank
        }
        pencilShortcutsEnabled = UserDefaults.standard.bool(forKey: "InfiniCanvas.pencilShortcuts")
        if let saved = UserDefaults.standard.string(forKey: "InfiniCanvas.penProfile"),
           let restored = PenProfile(rawValue: saved) { penProfile = restored }
        if UserDefaults.standard.object(forKey: "InfiniCanvas.fixedHighlighter") != nil {
            fixedHighlighter = UserDefaults.standard.bool(forKey: "InfiniCanvas.fixedHighlighter")
        }
        if let storedHeight = UserDefaults.standard.object(forKey: "InfiniCanvas.markerHeight") as? Double {
            markerHeight = CGFloat(storedHeight)
        }
        if let storedWidth = UserDefaults.standard.object(forKey: "InfiniCanvas.markerWidth") as? Double {
            markerWidth = CGFloat(storedWidth)
        }
        indexReady = true
    }

    static func paperBackground(_ style: PaperStyle) -> UIColor {
        guard style != .blank else { return UIColor(red: 0.991, green: 0.984, blue: 0.961, alpha: 1) }
        let tile = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: tile)
        let image = renderer.image { context in
            UIColor(red: 0.991, green: 0.984, blue: 0.961, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: tile))
            let cg = context.cgContext
            UIColor(red: 0.70, green: 0.77, blue: 0.78, alpha: 0.36).setStroke()
            cg.setLineWidth(0.55)
            switch style {
            case .blank: break
            case .ruled:
                cg.move(to: CGPoint(x: 0, y: 31.5)); cg.addLine(to: CGPoint(x: 32, y: 31.5)); cg.strokePath()
            case .grid:
                cg.move(to: CGPoint(x: 31.5, y: 0)); cg.addLine(to: CGPoint(x: 31.5, y: 32))
                cg.move(to: CGPoint(x: 0, y: 31.5)); cg.addLine(to: CGPoint(x: 32, y: 31.5)); cg.strokePath()
            case .dots:
                cg.setFillColor(UIColor(red: 0.65, green: 0.73, blue: 0.75, alpha: 0.55).cgColor)
                cg.fillEllipse(in: CGRect(x: 29.5, y: 29.5, width: 2, height: 2))
            }
        }
        // Screen-aligned visual paper aid; ink geometry is independent of the pattern.
        return UIColor(patternImage: image)
    }

    func attach(_ view: PKCanvasView) {
        canvas = view
        loading = true
        view.drawing = initialDrawing
        view.backgroundColor = Self.paperBackground(paper)
        applyPalmProtection()
        updateTool()
        loading = false
        refreshViewport()
    }

    func applyPalmProtection() {
        guard let view = canvas else { return }
        view.drawingPolicy = .pencilOnly
        // PencilKit's native finger navigation requires scrolling ENABLED.
        // Pencil-only drawing rejects finger/palm ink. The system handles
        // single-finger scrolling and two-finger pinch on the main canvas.
        view.isScrollEnabled = true
        view.panGestureRecognizer.minimumNumberOfTouches = 1
        configureNavigationRecognizers(view)
        status = "Pencil-only ink · finger to pan · pinch to zoom"
    }

    private func configureNavigationRecognizers(_ view: PKCanvasView) {
        let coveredByOverlay = tool == .capture || (tool == .marker && fixedHighlighter)
        view.panGestureRecognizer.isEnabled = !coveredByOverlay
        view.pinchGestureRecognizer?.isEnabled = !coveredByOverlay
    }

    func updateTool() {
        guard let view = canvas else { return }
        configureNavigationRecognizers(view)
        switch tool {
        case .pen:
            let inkType: PKInkingTool.InkType
            switch penProfile {
            case .fluid: inkType = .pen
            case .fountain: inkType = .fountainPen
            case .monoline: inkType = .monoline
            }
            view.tool = PKInkingTool(inkType, color: inkColor, width: strokeWidth)
        case .pencil: view.tool = PKInkingTool(.pencil, color: inkColor, width: strokeWidth)
        case .marker:
            // Native fallback keeps tilt behavior; the fixed-nib overlay commits its own vectors.
            view.tool = PKInkingTool(.marker, color: inkColor.withAlphaComponent(0.52), width: strokeWidth * 4)
        case .eraser:
            view.tool = PKEraserTool(eraserPrecision == .detail ? .bitmap : .vector, width: eraserWidth)
        case .capture: view.tool = PKLassoTool()
        }
    }

    // MARK: - Coordinate conversions for all overlay PencilKit interactions
    // UIScrollView.bounds.origin tracks contentOffset. Convert from the overlay
    // to WINDOW coordinates first, and then include the offset exactly once.
    private func viewportPoint(_ point: CGPoint, from overlay: UIView, in view: PKCanvasView) -> CGPoint? {
        guard let window = view.window, overlay.window === window else { return nil }
        let windowPoint = overlay.convert(point, to: window)
        let visibleCanvas = view.convert(view.bounds, to: window)
        return CGPoint(x: windowPoint.x - visibleCanvas.minX,
                       y: windowPoint.y - visibleCanvas.minY)
    }

    private func drawingPoint(_ point: CGPoint, from overlay: UIView, in view: PKCanvasView) -> CGPoint? {
        guard let viewport = viewportPoint(point, from: overlay, in: view) else { return nil }
        return CanvasGeometry.drawingPoint(viewport: viewport,
                                           offset: view.contentOffset,
                                           scale: view.zoomScale)
    }

    private func zoomPreservingAnchor(_ requestedScale: CGFloat, at viewport: CGPoint, in view: PKCanvasView) {
        let originalZoom = max(view.zoomScale, 0.0001)
        let originalOffset = view.contentOffset
        let newScale = min(view.maximumZoomScale, max(view.minimumZoomScale, requestedScale))
        guard abs(newScale - originalZoom) > 0.000001 else { return }
        view.setZoomScale(newScale, animated: false)
        let nextOffset = CanvasGeometry.offsetPreservingAnchor(
            originalOffset: originalOffset,
            originalZoom: originalZoom,
            targetZoom: view.zoomScale,
            viewportAnchor: viewport
        )
        view.setContentOffset(nextOffset, animated: false)
        refreshViewport()
    }

    // Called only when a fixed-highlighter Pencil stroke has FINISHED. Never save partial frames.
    // PKStrokePoint's azimuth and point dimensions are fixed; the backing PKDrawing stays editable.
    func commitFixedMarker(_ screenPoints: [CGPoint], in overlay: UIView) {
        guard let view = canvas, screenPoints.count >= 1 else { return }
        let height = max(6, markerHeight)
        let width = max(2, markerWidth)
        var samples: [PKStrokePoint] = []
        for (index, screen) in screenPoints.enumerated() {
            guard let world = drawingPoint(screen, from: overlay, in: view) else { return }
            samples.append(PKStrokePoint(location: world,
                                         timeOffset: Double(index) / 120.0,
                                         size: CGSize(width: width, height: height),
                                         opacity: 0.43, force: 0.5,
                                         azimuth: .pi / 2, altitude: .pi / 2))
        }
        guard !samples.isEmpty else { return }
        // Duplicate a single dab slightly: PencilKit interpolation expects a path.
        if samples.count == 1 {
            var second = samples[0]
            second = PKStrokePoint(location: CGPoint(x: samples[0].location.x + 0.01,
                                                     y: samples[0].location.y),
                                   timeOffset: 1.0 / 120.0,
                                   size: CGSize(width: width, height: height), opacity: 0.43,
                                   force: 0.5, azimuth: .pi / 2, altitude: .pi / 2)
            samples.append(second)
        }
        let newStroke = PKStroke(ink: PKInk(.marker, color: inkColor.withAlphaComponent(0.52)),
                                 path: PKStrokePath(controlPoints: samples, creationDate: Date()),
                                 transform: .identity, mask: nil)
        checkpoint()
        loading = true
        view.drawing = PKDrawing(strokes: view.drawing.strokes + [newStroke])
        loading = false
        isSaved = false
        scheduleSave()
        status = "Vertical marker saved as editable ink"
    }

    // Custom pinch is only used over full-screen Pencil overlays.
    // Main canvas uses native UIScrollView zoom, never competing recognizers.
    func handleFingerPinch(_ recognizer: UIPinchGestureRecognizer, in host: UIView) {
        guard let view = canvas else { return }
        switch recognizer.state {
        case .began:
            pinchActivated = false
            pinchStartingZoom = view.zoomScale
            let midpoint = recognizer.location(in: host)
            guard let viewport = viewportPoint(midpoint, from: host, in: view) else { return }
            pinchWorldAnchor = CanvasGeometry.drawingPoint(
                viewport: viewport, offset: view.contentOffset, scale: view.zoomScale)
        case .changed:
            guard recognizer.numberOfTouches >= 2 else { return }
            if !pinchActivated {
                let a = recognizer.location(ofTouch: 0, in: host)
                let b = recognizer.location(ofTouch: 1, in: host)
                guard hypot(a.x - b.x, a.y - b.y) > 75,
                      abs(recognizer.scale - 1) > 0.055 else { return }
                pinchActivated = true
            }
            guard let midpoint = viewportPoint(recognizer.location(in: host), from: host, in: view) else { return }
            let requested = min(view.maximumZoomScale, max(view.minimumZoomScale,
                                pinchStartingZoom * recognizer.scale))
            view.setZoomScale(requested, animated: false)
            let actual = view.zoomScale
            view.setContentOffset(
                CGPoint(x: pinchWorldAnchor.x * actual - midpoint.x,
                        y: pinchWorldAnchor.y * actual - midpoint.y),
                animated: false)
            refreshViewport()
        case .ended, .cancelled, .failed:
            if pinchActivated { saveViewPosition() }
            pinchActivated = false
        default: break
        }
    }

    // When Lasso is on top of the canvas, its two-finger pan forwards navigation
    // here instead of blocking it. RestSafe still forbids finger panning.
    func handleLassoPan(_ recognizer: UIPanGestureRecognizer, in host: UIView) {
        guard let view = canvas else { return }
        let translation = recognizer.translation(in: host)
        // Two recognizers can run simultaneously. Pinch owns zoom, and panning
        // must not also offset the canvas while the fingers spread.
        let pinching = host.gestureRecognizers?.contains(where: {
            guard let gesture = $0 as? UIPinchGestureRecognizer else { return false }
            return gesture.state == .began || gesture.state == .changed
        }) ?? false
        switch recognizer.state {
        case .began:
            panStartingOffset = view.contentOffset
            panStartingTranslation = translation
        case .changed:
            if pinching {
                // Resume from the current zoomed viewport without applying
                // all of the translation that accumulated during the pinch.
                panStartingOffset = view.contentOffset
                panStartingTranslation = translation
                return
            }
            let delta = CGPoint(x: translation.x - panStartingTranslation.x,
                                y: translation.y - panStartingTranslation.y)
            view.setContentOffset(CGPoint(x: panStartingOffset.x - delta.x,
                                          y: panStartingOffset.y - delta.y), animated: false)
            refreshViewport()
        case .ended, .cancelled, .failed:
            saveViewPosition()
        default: break
        }
    }

    func toggleEraser() {
        if tool == .eraser { tool = rememberedTool } else { rememberedTool = tool; tool = .eraser }
    }

    func showSystemTools() {
        guard let view = canvas else { return }
        if toolPicker == nil { toolPicker = PKToolPicker() }
        guard let picker = toolPicker else { return }
        picker.addObserver(view)
        view.becomeFirstResponder()
        picker.setVisible(true, forFirstResponder: view)
        status = "Native Apple tool palette"
    }

    func toggleRuler() {
        canvas?.isRulerActive.toggle()
        status = canvas?.isRulerActive == true ? "Ruler on" : "Ruler off"
    }

    func saveViewPosition() {
        let center = worldCenter()
        UserDefaults.standard.set(Double(center.x), forKey: "infini.centerX")
        UserDefaults.standard.set(Double(center.y), forKey: "infini.centerY")
        UserDefaults.standard.set(Double(zoom), forKey: "infini.zoom")
    }
    func restoreViewPosition() {
        guard let view = canvas, view.bounds.width > 1 else { return }
        let prefs = UserDefaults.standard
        let x = prefs.object(forKey: "infini.centerX") as? Double ?? 8000
        let y = prefs.object(forKey: "infini.centerY") as? Double ?? 8000
        let scale = CGFloat(prefs.object(forKey: "infini.zoom") as? Double ?? 1)
        view.setZoomScale(min(max(scale, view.minimumZoomScale), view.maximumZoomScale), animated: false)
        let point = CGPoint(x: x, y: y)
        view.setContentOffset(CGPoint(x: point.x * view.zoomScale - view.bounds.width / 2, y: point.y * view.zoomScale - view.bounds.height / 2), animated: false)
        refreshViewport()
    }
    func refreshViewport() {
        guard let view = canvas else { return }
        zoom = view.zoomScale
        offset = view.contentOffset
    }
    func worldCenter() -> CGPoint {
        guard let view = canvas else { return CGPoint(x: 8000, y: 8000) }
        return CGPoint(x: (view.contentOffset.x + view.bounds.width / 2) / max(view.zoomScale, 0.01),
                       y: (view.contentOffset.y + view.bounds.height / 2) / max(view.zoomScale, 0.01))
    }
    func screenPoint(for area: CanvasArea) -> CGPoint {
        CanvasGeometry.viewportPoint(drawing: CGPoint(x: area.x, y: area.y), offset: offset, scale: zoom)
    }
    func zoomToOverview() {
        guard let view = canvas else { return }
        zoomPreservingAnchor(0.14, at: CGPoint(x: view.bounds.width / 2, y: view.bounds.height / 2), in: view)
        status = "Overview · 4.5%–3200% available"
    }
    func zoomToWriting() {
        guard let view = canvas else { return }
        zoomPreservingAnchor(1, at: CGPoint(x: view.bounds.width / 2, y: view.bounds.height / 2), in: view)
    }
    func zoomTo(_ scale: CGFloat) {
        guard let view = canvas else { return }
        zoomPreservingAnchor(scale, at: CGPoint(x: view.bounds.width / 2,
                                               y: view.bounds.height / 2), in: view)
        saveViewPosition()
    }
    func zoomBy(_ factor: CGFloat) {
        guard let view = canvas else { return }
        zoomPreservingAnchor(view.zoomScale * factor, at: CGPoint(x: view.bounds.width / 2,
                                      y: view.bounds.height / 2), in: view)
    }

    func drawingChanged() {
        // The selection is temporarily detached only for live visual dragging.
        // Never treat that intermediate drawing as a user edit or autosave target.
        guard !loading, dragOriginal == nil else { return }
        isSaved = false
        // New PencilKit writing supersedes an earlier manual-transform undo step.
        // This prevents Undo from unexpectedly moving old selections instead of erasing fresh ink.
        editUndo.removeAll(); editRedo.removeAll()
        scheduleSave()
        if selectionActive { clearSelection() }
    }
    func scheduleSave() {
        saveWork?.cancel()
        let job = DispatchWorkItem { [weak self] in self?.saveImmediately() }
        saveWork = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: job)
    }

    func saveImmediately() {
        saveWork?.cancel()
        // Never persist the temporary "selected ink hidden" drawing used by live lasso dragging.
        if dragOriginal != nil { cancelSelectionDrag() }
        guard let view = canvas else { return }
        saveViewPosition()
        do {
            let data = view.drawing.dataRepresentation()
            // Atomic write first; the recovery file is always from an earlier known good save.
            if FileManager.default.fileExists(atPath: drawingFile.path) {
                createPeriodicRevisionIfNeeded()
                // Atomically replace recovery from a known-good drawing. Never
                // erase the prior recovery copy before the new copy is secured.
                let previous = try Data(contentsOf: drawingFile)
                try previous.write(to: recoveryFile, options: .atomic)
            }
            try data.write(to: drawingFile, options: [.atomic, .completeFileProtectionUnlessOpen])
            try persistIndex()
            isSaved = true
            status = "Saved on iPad"
            createAutomaticBackupIfNeeded(drawingData: data)
        } catch {
            isSaved = false
            status = "Save error — export a backup"
        }
    }
    private func createPeriodicRevisionIfNeeded() {
        guard Date().timeIntervalSince(lastRevisionDate) > 600 else { return }
        let name = "revision-\(Int(Date().timeIntervalSince1970)).pkdrawing"
        let path = revisionsFolder.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: drawingFile, to: path)
            lastRevisionDate = .now
            let versions = revisionFiles
            if versions.count > 12 {
                for old in versions.dropFirst(12) { try? FileManager.default.removeItem(at: old) }
            }
        } catch {
            // The main atomic autosave still runs even if revision creation fails.
        }
    }
    var revisionFiles: [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: revisionsFolder,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return entries.filter { $0.pathExtension == "pkdrawing" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    func restoreRevision(_ source: URL) -> Bool {
        guard source.deletingLastPathComponent() == revisionsFolder else { return false }
        guard let data = try? Data(contentsOf: source), let previous = try? PKDrawing(data: data) else {
            status = "Couldn't load that revision"; return false
        }
        // Always save the state being replaced as an explicit rollback file.
        if let current = canvas?.drawing.dataRepresentation() {
            try? current.write(to: recoveryFile, options: .atomic)
        }
        loading = true
        canvas?.drawing = previous
        loading = false
        clearSelection()
        isSaved = false
        scheduleSave()
        status = "Recovered previous ink revision"
        return true
    }

    private func persistIndex() throws {
        guard indexReady else { return }
        let model = currentIndex()
        try JSONEncoder().encode(model).write(to: indexFile, options: .atomic)
    }
    private func currentIndex() -> CanvasIndex {
        CanvasIndex(areas: areas, clips: clips, paper: paper, indexVersion: 5,
            textNotes: textNotes, lectureSessions: lectureSessions)
    }

    private func packageBackup(drawingData: Data) -> CompleteBackup {
        var pngs = [String: Data](), vectors = [String: Data](), audio = [String: Data]()
        for clip in clips {
            if let data = try? Data(contentsOf: clipURL(clip)) { pngs[clip.imageName] = data }
            if let name = clip.drawingName, let data = try? Data(contentsOf: clipsFolder.appendingPathComponent(name)) {
                vectors[name] = data
            }
        }
        for lecture in lectureSessions {
            if let data = try? Data(contentsOf: audioFolder.appendingPathComponent(lecture.audioFile)) {
                audio[lecture.audioFile] = data
            }
        }
        let artFile = directory.appendingPathComponent("Artwork", isDirectory: true)
            .appendingPathComponent("artwork.json")
        let artwork = try? Data(contentsOf: artFile)
        return CompleteBackup(format: "infini-canvas-native-v5", exportedAt: .now,
            drawing: drawingData, index: currentIndex(), clipImages: pngs,
            clipDrawings: vectors, audioFiles: audio, artworkData: artwork)
    }

    private func createAutomaticBackupIfNeeded(drawingData: Data) {
        guard !recording else { return }
        let key = "InfiniCanvas.lastAutomaticBackup"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 24 * 3600 else { return }
        do {
            let backup = packageBackup(drawingData: drawingData)
            let data = try JSONEncoder().encode(backup)
            let path = autosaveFolder.appendingPathComponent("snapshot-\(Int(Date().timeIntervalSince1970)).json")
            try data.write(to: path, options: .atomic)
            UserDefaults.standard.set(Date(), forKey: key)
            let files = automaticBackupFiles
            if files.count > 7 { for old in files.dropFirst(7) { try? FileManager.default.removeItem(at: old) } }
        } catch {
            status = "Saved ink; automatic full backup needs retry"
        }
    }
    var automaticBackupFiles: [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: autosaveFolder,
            includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    func restoreAutomaticBackup(_ url: URL) -> Bool { restoreCompleteBackup(url) }

    func saveIndex() {
        guard indexReady else { return }
        do { try persistIndex() } catch { status = "Library save failed" }
    }

    private func checkpoint() {
        guard let view = canvas else { return }
        let current = view.drawing
        editUndo.append(current)
        if editUndo.count > 30 { editUndo.removeFirst() }
        editRedo.removeAll()
    }
    func undo() {
        if let previous = editUndo.popLast(), let view = canvas {
            editRedo.append(view.drawing)
            loading = true; view.drawing = previous; loading = false
            clearSelection(); scheduleSave()
        } else if let manager = canvas?.undoManager, manager.canUndo {
            manager.undo()
            scheduleSave()
        } else {
            status = "Nothing to undo yet"
        }
    }
    func redo() {
        if let next = editRedo.popLast(), let view = canvas {
            editUndo.append(view.drawing)
            loading = true; view.drawing = next; loading = false
            clearSelection(); scheduleSave()
        } else if let manager = canvas?.undoManager, manager.canRedo {
            manager.redo()
            scheduleSave()
        } else {
            status = "Nothing to redo yet"
        }
    }
    func clearSelection() {
        if dragOriginal != nil { cancelSelectionDrag() }
        selectedIndices = []
        selectionActive = false
    }


    func captureLasso(_ points: [CGPoint], from overlay: UIView) {
        guard let view = canvas, points.count >= 4 else { status = "Circle an area"; return }
        // Select every PKStroke type: pen, pencil, fountain, highlighter or custom marker.
        let locations = points.compactMap { drawingPoint($0, from: overlay, in: view) }
        guard locations.count == points.count else {
            status = "Lasso couldn't read the visible drawing region"; return
        }
        let polygon = UIBezierPath()
        polygon.move(to: locations[0]); for point in locations.dropFirst() { polygon.addLine(to: point) }; polygon.close()
        guard polygon.bounds.width > 4, polygon.bounds.height > 4 else { return }

        var indices = Set<Int>()
        var selected: [PKStroke] = []
        for (i, stroke) in view.drawing.strokes.enumerated() {
            guard stroke.renderBounds.intersects(polygon.bounds) else { continue }
            let center = CGPoint(x: stroke.renderBounds.midX, y: stroke.renderBounds.midY)
            var inside = polygon.contains(center)
            if !inside {
                let strideSize = max(1, stroke.path.count / 120)
                for j in stride(from: 0, to: stroke.path.count, by: strideSize) {
                    if polygon.contains(stroke.path[j].location.applying(stroke.transform)) { inside = true; break }
                }
            }
            if inside { indices.insert(i); selected.append(stroke) }
        }
        guard !selected.isEmpty else {
            clearSelection(); status = "No pen, pencil or highlighter strokes in selection"; return
        }
        let selectedDrawing = PKDrawing(strokes: selected)
        let bounds = selectedDrawing.bounds.insetBy(dx: -18, dy: -18)
        guard bounds.width > 1, bounds.height > 1, bounds.width < 9000, bounds.height < 9000 else {
            status = "Selection too large to clip"; return
        }
        let image = selectedDrawing.image(from: bounds, scale: 2.5)
        guard let png = image.pngData() else { status = "Clip rendering failed"; return }
        let id = UUID()
        let file = "\(id.uuidString).png"
        let vector = "\(id.uuidString).pkdrawing"
        do {
            try png.write(to: clipsFolder.appendingPathComponent(file), options: .atomic)
            try selectedDrawing.dataRepresentation().write(to: clipsFolder.appendingPathComponent(vector), options: .atomic)
            let src = CGPoint(x: selectedDrawing.bounds.midX, y: selectedDrawing.bounds.midY)
            let closest = activeAreas.min(by: { distance($0, src) < distance($1, src) })
            let label = closest.flatMap { distance($0, src) < 2000 ? $0.title : nil }
            let clip = SavedClip(id: id, title: "Clip \(clips.filter { $0.isTrashed != true }.count + 1)",
                createdAt: .now, imageName: file, strokeCount: selected.count,
                drawingName: vector, course: label.flatMap { Self.category(for: $0) },
                sourceX: Double(src.x), sourceY: Double(src.y),
                audioSessionID: currentRecordingID,
                audioSecond: recording ? recorder?.currentTime : nil)
            clips.insert(clip, at: 0)
            if let recordingID = currentRecordingID,
               let index = lectureSessions.firstIndex(where: { $0.id == recordingID }) {
                lectureSessions[index].marks.append(LectureMark(seconds: recorder?.currentTime ?? 0,
                    x: Double(src.x), y: Double(src.y), clipID: id))
            }
            latestClip = clip
            selectedIndices = indices
            selectionActive = true
            saveIndex()
            status = "Captured \(selected.count) strokes · OCR indexing"
            recognizeText(image, clipID: id)
        } catch { status = "Clip save failed" }
    }

    private func recognizeText(_ image: UIImage, clipID: UUID) {
        guard let cgImage = image.cgImage else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: " ")
                Task { @MainActor [weak self] in
                    guard let self, let i = self.clips.firstIndex(where: { $0.id == clipID }) else { return }
                    self.clips[i].recognizedText = text
                    self.saveIndex()
                    self.status = text.isEmpty ? "Clip saved" : "Clip saved and searchable"
                }
            } catch { /* OCR is best effort: PNG and vector ink already saved. */ }
        }
    }

    private func distance(_ area: CanvasArea, _ point: CGPoint) -> CGFloat {
        hypot(CGFloat(area.x) - point.x, CGFloat(area.y) - point.y)
    }
    static func category(for title: String) -> String {
        let value = title.uppercased()
        let known = ["PSYC", "FND", "LLS", "CMDS", "COGS", "PHIL", "LING", "MATH", "CHEM", "BIOL", "HIST"]
        if let direct = known.first(where: { value.contains($0) }) { return direct }
        let psychologyTerms = ["PSYCHOLOGY", "NEURON", "CLASSICAL CONDITIONING",
            "OPERANT CONDITIONING", "COGNITIVE PSYCHOLOGY", "BEHAVIOURISM", "BEHAVIORISM",
            "PSYCHOACTIVE", "SENSATION AND PERCEPTION"]
        if psychologyTerms.contains(where: { value.contains($0) }) { return "PSYC" }
        return "Unsorted"
    }

    // Detach the selected ink once and show a cached image in the lasso overlay.
    // That image follows the Pencil every frame without re-rendering PKDrawing.
    // Commit the vector transform once on Pencil lift; cancel restores original ink.
    func beginSelectionDrag() -> (UIImage, CGRect)? {
        guard let view = canvas, selectionActive, !selectedIndices.isEmpty, dragOriginal == nil else { return nil }
        let source = view.drawing
        let strokes = source.strokes
        let selected = strokes.enumerated().compactMap { selectedIndices.contains($0.offset) ? $0.element : nil }
        guard !selected.isEmpty else { return nil }
        let drawing = PKDrawing(strokes: selected)
        let bounds = drawing.bounds.insetBy(dx: -10, dy: -10)
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let image = drawing.image(from: bounds, scale: 2)
        checkpoint()
        dragOriginal = source
        dragSelected = selected
        dragRemaining = strokes.enumerated().compactMap { selectedIndices.contains($0.offset) ? nil : $0.element }
        dragBounds = bounds
        loading = true
        view.drawing = PKDrawing(strokes: dragRemaining)
        loading = false
        let rect = CGRect(x: bounds.minX * view.zoomScale - view.contentOffset.x,
                          y: bounds.minY * view.zoomScale - view.contentOffset.y,
                          width: bounds.width * view.zoomScale,
                          height: bounds.height * view.zoomScale)
        return (image, rect)
    }
    func finishSelectionDrag(screenDelta delta: CGSize) {
        guard let view = canvas, dragOriginal != nil else { return }
        let zoom = max(0.0001, view.zoomScale)
        let transform = CGAffineTransform(translationX: delta.width / zoom, y: delta.height / zoom)
        let moved = dragSelected.map { stroke in
            PKStroke(ink: stroke.ink, path: stroke.path,
                transform: stroke.transform.concatenating(transform), mask: stroke.mask)
        }
        loading = true
        view.drawing = PKDrawing(strokes: dragRemaining + moved)
        loading = false
        selectedIndices = Set(dragRemaining.count..<(dragRemaining.count + moved.count))
        dragOriginal = nil
        dragSelected = []
        dragRemaining = []
        isSaved = false
        scheduleSave()
        status = "Moved ink with live preview · Undo available"
    }
    func cancelSelectionDrag() {
        if let source = dragOriginal, let view = canvas {
            loading = true
            view.drawing = source
            loading = false
        }
        dragOriginal = nil
        dragSelected = []
        dragRemaining = []
    }

    private func translateSelected(dx: CGFloat, dy: CGFloat) {
        guard let view = canvas, selectionActive, !selectedIndices.isEmpty else { return }
        guard abs(dx) + abs(dy) > 0.25 else { return }
        checkpoint()
        var strokes = view.drawing.strokes
        for i in selectedIndices {
            guard strokes.indices.contains(i) else { continue }
            let stroke = strokes[i]
            strokes[i] = PKStroke(ink: stroke.ink, path: stroke.path,
                transform: stroke.transform.concatenating(CGAffineTransform(translationX: dx, y: dy)), mask: stroke.mask)
        }
        loading = true; view.drawing = PKDrawing(strokes: strokes); loading = false
        isSaved = false; scheduleSave()
        status = "Moved selection"
    }
    func moveSelection(to area: CanvasArea) {
        guard let view = canvas, selectionActive else { return }
        let strokes = selectedIndices.compactMap { i in view.drawing.strokes.indices.contains(i) ? view.drawing.strokes[i] : nil }
        guard !strokes.isEmpty else { return }
        let bounds = PKDrawing(strokes: strokes).bounds
        translateSelected(dx: CGFloat(area.x) - bounds.midX, dy: CGFloat(area.y) - bounds.midY)
        goToArea(area)
        status = "Moved selected ink to \(area.title)"
    }
    func deleteSelection() {
        guard let view = canvas, selectionActive else { return }
        checkpoint()
        loading = true
        view.drawing = PKDrawing(strokes: view.drawing.strokes.enumerated().compactMap { i, s in selectedIndices.contains(i) ? nil : s })
        loading = false
        clearSelection(); isSaved = false; scheduleSave()
        status = "Ink removed · Undo to restore"
    }

    func clipURL(_ clip: SavedClip) -> URL { clipsFolder.appendingPathComponent(clip.imageName) }
    func clipImage(_ clip: SavedClip) -> UIImage? { UIImage(contentsOfFile: clipURL(clip).path) }
    func copyClip(_ clip: SavedClip) {
        guard let image = clipImage(clip) else { return }
        UIPasteboard.general.image = image
        status = "Clipping copied · paste into ChatGPT"
    }
    func renameClip(_ clip: SavedClip, to newTitle: String) {
        guard let i = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        clips[i].title = newTitle; saveIndex()
    }
    func markReview(_ clip: SavedClip) {
        guard let i = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        clips[i].nextReview = Date()
        clips[i].reviewIntervalDays = 1
        saveIndex(); status = "Added to study queue"
    }
    func completeReview(_ clip: SavedClip, rating: ReviewRating = .good) {
        guard let i = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        let prior = clips[i].reviewIntervalDays ?? 1
        let days: Int
        switch rating {
        case .again: days = 1
        case .hard: days = max(2, prior)
        case .good: days = max(4, Int(Double(prior) * 1.9))
        case .easy: days = max(7, Int(Double(prior) * 2.7))
        }
        clips[i].nextReview = Calendar.current.date(byAdding: .day, value: days, to: .now)
        clips[i].reviewIntervalDays = days
        clips[i].reviewCount = (clips[i].reviewCount ?? 0) + 1
        saveIndex(); status = "Next review in \(days) days"
    }
    func copyStudyPrompt(_ clip: SavedClip) {
        let recognized = clip.recognizedText?.isEmpty == false ? (clip.recognizedText ?? "") : "[Image needed: attach the clip after pasting]"
        let content = """
        I am studying this handwritten note from \(clip.course ?? "my coursework").
        Handwriting recognition (may contain errors): \(recognized)
        Please explain the underlying idea accurately, then quiz me with 5 distinct single-answer MCQs.
        Ask only one clarification if the handwriting is illegible. Focus on retrieval and misconceptions.
        """
        UIPasteboard.general.string = content
        status = "Study prompt copied · paste into ChatGPT with image"
    }
    func togglePin(_ clip: SavedClip) {
        guard let i = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        clips[i].isPinned = clips[i].isPinned != true; saveIndex()
    }
    func deleteClip(_ clip: SavedClip) {
        guard let i = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        clips[i].isTrashed = true; saveIndex(); status = "Clip moved to Trash"
    }
    func restoreClip(_ clip: SavedClip) {
        guard let i = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        clips[i].isTrashed = false; saveIndex()
    }
    var activeClips: [SavedClip] { clips.filter { $0.isTrashed != true } }
    var discardedClips: [SavedClip] { clips.filter { $0.isTrashed == true } }
    var dueClips: [SavedClip] { activeClips.filter { ($0.nextReview ?? .distantFuture) <= .now } }
    var activeAreas: [CanvasArea] { areas.filter { $0.isTrashed != true && $0.isHidden != true } }
    var focusedArea: CanvasArea? { areas.first { $0.id == focusAreaID && $0.isTrashed != true } }
    func focusOnArea(_ area: CanvasArea) {
        focusAreaID = area.id
        goToArea(area)
        status = "Other areas hidden visually · ink preserved"
    }
    func revealAllAreas() {
        focusAreaID = nil
        status = "All areas visible"
    }

    var discardedAreas: [CanvasArea] { areas.filter { $0.isTrashed == true } }

    func pasteClipAsInk(_ clip: SavedClip) {
        guard let filename = clip.drawingName,
              let data = try? Data(contentsOf: clipsFolder.appendingPathComponent(filename)),
              let stored = try? PKDrawing(data: data), let view = canvas else {
            status = "Older clips have image only · use Copy"; return
        }
        checkpoint()
        let center = worldCenter()
        let dx = center.x - stored.bounds.midX, dy = center.y - stored.bounds.midY
        let pasted = stored.strokes.map { stroke in
            PKStroke(ink: stroke.ink, path: stroke.path,
                transform: stroke.transform.concatenating(CGAffineTransform(translationX: dx, y: dy)), mask: stroke.mask)
        }
        loading = true; view.drawing = PKDrawing(strokes: view.drawing.strokes + pasted); loading = false
        isSaved = false; scheduleSave(); status = "Pasted editable ink"
    }
    func goToClip(_ clip: SavedClip) {
        guard let x = clip.sourceX, let y = clip.sourceY, let view = canvas else { return }
        goToWorld(CGPoint(x: x, y: y), in: view)
    }

    func makeAreaFromSelection() {
        guard let view = canvas, selectionActive else { status = "Circle handwriting first"; return }
        let strokes = selectedIndices.compactMap { i in view.drawing.strokes.indices.contains(i) ? view.drawing.strokes[i] : nil }
        guard !strokes.isEmpty else { return }
        let bounds = PKDrawing(strokes: strokes).bounds.insetBy(dx: -100, dy: -100)
        let suggested = latestClip?.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = suggested.isEmpty ? "Area \(activeAreas.count + 1)" : String(suggested.prefix(55))
        areas.append(CanvasArea(id: UUID(), title: label,
            x: Double(bounds.midX), y: Double(bounds.midY),
            width: Double(max(bounds.width, 350)), height: Double(max(bounds.height, 260))))
        saveIndex()
        status = "Selected writing grouped under one area · ink unchanged"
    }

    func autoNameAndAddArea() {
        guard let view = canvas else { return }
        let center = worldCenter()
        let radius = min(1400, max(500, 650 / max(view.zoomScale, 0.1)))
        let rect = CGRect(x: center.x - radius, y: center.y - radius * 0.65,
                          width: radius * 2, height: radius * 1.3)
        let nearby = view.drawing.strokes.filter { $0.renderBounds.intersects(rect) }
        let fallback = "Area \(activeAreas.count + 1)"
        guard !nearby.isEmpty else { addArea(fallback); return }
        let image = PKDrawing(strokes: nearby).image(from: rect, scale: 1.6)
        guard let cg = image.cgImage else { addArea(fallback); return }
        Task.detached(priority: .utility) { [weak self] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            let lines: [String]
            do {
                try handler.perform([request])
                lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            } catch { lines = [] }
            await MainActor.run { [weak self] in
                guard let self else { return }
                let recognized = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                let course = Self.category(for: recognized)
                let cleaned = recognized.replacingOccurrences(of: "\n", with: " ")
                let label: String
                if course != "Unsorted" {
                    label = "\(course) · \(String(cleaned.prefix(42)))"
                } else if !cleaned.isEmpty {
                    label = String(cleaned.prefix(52))
                } else { label = fallback }
                self.addArea(label)
                self.status = recognized.isEmpty ? "Area added · rename anytime" : "Area named from handwriting · check label"
            }
        }
    }

    func addArea(_ title: String) {
        let p = worldCenter()
        areas.append(CanvasArea(id: UUID(), title: title, x: Double(p.x), y: Double(p.y),
            width: 2400, height: 1600))
        saveIndex(); status = "Area marked on this canvas"
    }
    func goToArea(_ area: CanvasArea) {
        guard let view = canvas else { return }
        goToWorld(CGPoint(x: area.x, y: area.y), in: view)
    }
    private func goToWorld(_ point: CGPoint, in view: PKCanvasView) {
        let scale = view.zoomScale
        let target = CGPoint(x: point.x * scale - view.bounds.width / 2, y: point.y * scale - view.bounds.height / 2)
        view.setContentOffset(target, animated: true)
    }
    func deleteArea(_ area: CanvasArea) {
        guard let i = areas.firstIndex(where: { $0.id == area.id }) else { return }
        areas[i].isTrashed = true; saveIndex(); status = "Area label in Trash · ink untouched"
    }
    func restoreArea(_ area: CanvasArea) {
        guard let i = areas.firstIndex(where: { $0.id == area.id }) else { return }
        areas[i].isTrashed = false; saveIndex()
    }
    func renameArea(_ area: CanvasArea, to name: String) {
        guard let i = areas.firstIndex(where: { $0.id == area.id }) else { return }
        areas[i].title = name; saveIndex()
    }
    func clipsNear(_ area: CanvasArea) -> Int {
        activeClips.filter { clip in
            guard let x = clip.sourceX, let y = clip.sourceY else { return false }
            return hypot(x - area.x, y - area.y) < 2000
        }.count
    }

    var groupedAreas: [(String, [CanvasArea])] {
        let groups = Dictionary(grouping: activeAreas, by: { Self.category(for: $0.title) })
        return groups.keys.sorted().map { key in
            (key, (groups[key] ?? []).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
        }
    }

    var activeTextNotes: [TypedNote] { textNotes.filter { $0.isTrashed != true } }
    var discardedTextNotes: [TypedNote] { textNotes.filter { $0.isTrashed == true } }
    func addTextNote(_ body: String) {
        let pos = worldCenter()
        textNotes.append(TypedNote(id: UUID(), body: body, x: Double(pos.x), y: Double(pos.y)))
        saveIndex(); status = "Typed note added to canvas"
    }
    func editTextNote(_ note: TypedNote, text: String) {
        guard let index = textNotes.firstIndex(where: { $0.id == note.id }) else { return }
        textNotes[index].body = text
        saveIndex()
    }
    func moveTextNote(_ note: TypedNote, delta: CGSize) {
        guard let index = textNotes.firstIndex(where: { $0.id == note.id }) else { return }
        let z = Double(max(zoom, 0.01))
        textNotes[index].x += Double(delta.width) / z
        textNotes[index].y += Double(delta.height) / z
        saveIndex()
    }
    func trashTextNote(_ note: TypedNote) {
        guard let index = textNotes.firstIndex(where: { $0.id == note.id }) else { return }
        textNotes[index].isTrashed = true; saveIndex()
    }
    func restoreTextNote(_ note: TypedNote) {
        guard let index = textNotes.firstIndex(where: { $0.id == note.id }) else { return }
        textNotes[index].isTrashed = false; saveIndex()
    }
    func goToTextNote(_ note: TypedNote) {
        guard let view = canvas else { return }
        goToWorld(CGPoint(x: note.x, y: note.y), in: view)
    }

    func exportCanvasURL() -> URL? { saveImmediately(); return FileManager.default.fileExists(atPath: drawingFile.path) ? drawingFile : nil }
    func exportCompleteBackup() -> URL? {
        saveImmediately()
        guard let current = canvas?.drawing.dataRepresentation() else { return nil }
        let backup = packageBackup(drawingData: current)
        guard let data = try? JSONEncoder().encode(backup) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("InfiniCanvas-FullBackup-\(UUID().uuidString.prefix(8)).json")
        do { try data.write(to: url, options: .atomic); return url }
        catch { status = "Backup export failed"; return nil }
    }
    func restoreCompleteBackup(_ url: URL) -> Bool {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let backup = try JSONDecoder().decode(CompleteBackup.self, from: data)
            guard ["infini-canvas-native-v4", "infini-canvas-native-v5"].contains(backup.format)
                else { status = "Unknown backup format"; return false }
            let restored = try PKDrawing(data: backup.drawing)
            // Check optional art-document bytes before changing any current files.
            if let art = backup.artworkData {
                _ = try JSONDecoder().decode(ArtworkDocument.self, from: art)
            }
            // Preserve the current drawing as a rollback file before applying an import.
            if let current = canvas?.drawing.dataRepresentation() {
                try current.write(to: recoveryFile, options: .atomic)
            }
            for (name, data) in backup.clipImages where !name.contains("/") && !name.contains("..") {
                try data.write(to: clipsFolder.appendingPathComponent(name), options: .atomic)
            }
            for (name, data) in backup.clipDrawings where !name.contains("/") && !name.contains("..") {
                try data.write(to: clipsFolder.appendingPathComponent(name), options: .atomic)
            }
            for (name, data) in (backup.audioFiles ?? [:]) where !name.contains("/") && !name.contains("..") {
                try data.write(to: audioFolder.appendingPathComponent(name), options: .atomic)
            }
            lectureSessions = backup.index.lectureSessions ?? []
            areas = backup.index.areas
            textNotes = backup.index.textNotes ?? []
            clips = backup.index.clips
            paper = backup.index.paper ?? .blank
            loading = true; canvas?.drawing = restored; loading = false
            try backup.drawing.write(to: drawingFile, options: .atomic)
            try persistIndex()
            if let art = backup.artworkData {
                let artFolder = directory.appendingPathComponent("Artwork", isDirectory: true)
                try FileManager.default.createDirectory(at: artFolder, withIntermediateDirectories: true)
                let artFile = artFolder.appendingPathComponent("artwork.json")
                try art.write(to: artFile, options: .atomic)
            }
            isSaved = true; status = "Complete backup restored"
            return true
        } catch { status = "Backup import failed: \(error.localizedDescription)"; return false }
    }

    // MARK: Organization: non-destructive categories, with explicit preview + undo.
    func prepareOrganization() {
        var proposals = [UUID: String]()
        for clip in activeClips {
            let content = [clip.title, clip.recognizedText ?? "", clip.course ?? ""].joined(separator: " ")
            var category = Self.category(for: content)
            if category == "Unsorted", let x = clip.sourceX, let y = clip.sourceY {
                let point = CGPoint(x: x, y: y)
                if let nearest = activeAreas.min(by: { distance($0, point) < distance($1, point) }),
                    distance(nearest, point) < 2500 {
                    category = Self.category(for: nearest.title)
                }
            }
            if category != "Unsorted" && category != clip.course { proposals[clip.id] = category }
        }
        organizationProposal = proposals
        organizationPreview = true
        status = "Review suggested clip categories before applying"
    }
    func applyOrganization() {
        organizedUndo = [:]
        for (id, proposed) in organizationProposal {
            guard let i = clips.firstIndex(where: { $0.id == id }) else { continue }
            organizedUndo[id] = clips[i].course ?? "~none~"
            clips[i].course = proposed
        }
        organizationProposal = [:]
        organizationPreview = false
        saveIndex()
        status = "Categories organized · Undo available"
    }
    func undoOrganization() {
        for (id, value) in organizedUndo {
            if let i = clips.firstIndex(where: { $0.id == id }) {
                clips[i].course = value == "~none~" ? nil : value
            }
        }
        organizedUndo = [:]
        saveIndex()
        status = "Organization reversed"
    }

    // MARK: Lecture bookmarks and audio. Consent and audio recording permissions are required.
    func beginLectureRecording() {
        guard !recording else { return }
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if granted { self.startRecorder() }
                else { self.status = "Microphone access denied · enable it in Settings" }
            }
        }
    }
    private func startRecorder() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            audioPlayer?.stop(); playingSessionID = nil
            let id = UUID()
            let name = "lecture-\(id.uuidString).m4a"
            let url = audioFolder.appendingPathComponent(name)
            recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ])
            guard recorder?.record() == true else { status = "Audio recorder could not start"; return }
            currentRecordingID = id
            currentRecordingName = name
            recordingStartedAt = Date()
            recording = true
            recordingSeconds = 0
            lectureSessions.insert(LectureSession(id: id, title: "Lecture \(Date().formatted(date: .abbreviated, time: .shortened))",
                createdAt: .now, audioFile: name, duration: 0, marks: []), at: 0)
            recordingTimer?.invalidate()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.recordingSeconds = self?.recorder?.currentTime ?? 0 }
            }
            addLectureMark()
            saveIndex()
            status = "Recording lecture · markers link ink with time"
        } catch { status = "Could not start recording: \(error.localizedDescription)" }
    }
    func addLectureMark() {
        guard recording, let id = currentRecordingID,
              let index = lectureSessions.firstIndex(where: { $0.id == id }) else { return }
        let center = worldCenter()
        let second = recorder?.currentTime ?? recordingSeconds
        lectureSessions[index].marks.append(LectureMark(seconds: second,
            x: Double(center.x), y: Double(center.y)))
        saveIndex()
        status = "Lecture bookmark at \(Int(second))s · writing location saved"
    }
    func endLectureRecording() {
        guard recording else { return }
        let seconds = recorder?.currentTime ?? recordingSeconds
        recorder?.stop()
        recorder = nil
        recordingTimer?.invalidate(); recordingTimer = nil
        if let id = currentRecordingID,
            let i = lectureSessions.firstIndex(where: { $0.id == id }) {
            lectureSessions[i].duration = seconds
        }
        currentRecordingID = nil
        currentRecordingName = nil
        recording = false
        recordingSeconds = seconds
        saveIndex()
        if let current = canvas?.drawing.dataRepresentation() { createAutomaticBackupIfNeeded(drawingData: current) }
        status = "Recording saved in Lecture Library"
    }
    func playLecture(_ lecture: LectureSession, at second: Double = 0) {
        if recording { endLectureRecording() }
        do {
            let url = audioFolder.appendingPathComponent(lecture.audioFile)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.currentTime = min(max(0, second), lecture.duration)
            audioPlayer?.play()
            playingSessionID = lecture.id
            status = "Playing \(lecture.title) from \(Int(second))s"
        } catch { status = "Lecture audio unavailable: \(error.localizedDescription)" }
    }
    func stopLecturePlayback() {
        audioPlayer?.stop(); audioPlayer = nil; playingSessionID = nil
        status = "Lecture paused"
    }
    func goToLectureMark(_ lecture: LectureSession, mark: LectureMark) {
        guard let view = canvas else { return }
        goToWorld(CGPoint(x: mark.x, y: mark.y), in: view)
        playLecture(lecture, at: mark.seconds)
    }
    func playFromClip(_ clip: SavedClip) {
        guard let id = clip.audioSessionID,
              let lecture = lectureSessions.first(where: { $0.id == id }) else {
            status = "This clipping has no lecture audio marker"; return
        }
        playLecture(lecture, at: clip.audioSecond ?? 0)
        goToClip(clip)
    }
    func renameLecture(_ lecture: LectureSession, name: String) {
        guard let i = lectureSessions.firstIndex(where: { $0.id == lecture.id }) else { return }
        lectureSessions[i].title = name; saveIndex()
    }

}
