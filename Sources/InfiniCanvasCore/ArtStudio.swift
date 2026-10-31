import SwiftUI
import UIKit
import PencilKit

// Native layered ART DOCUMENT, deliberately independent from the boundless study canvas.
// Layers are editable PKDrawings, not flattened screenshots. Fixed-format image export
// is separate, so reopening the document never destroys the editable layer structure.
struct ArtworkLayer: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var drawing: Data = PKDrawing().dataRepresentation()
    var opacity: Double = 1
    var isVisible: Bool = true
    var isLocked: Bool = false
}

struct ArtworkDocument: Codable {
    var layers: [ArtworkLayer]
    var selected: UUID
}

enum ArtBrush: String, CaseIterable, Identifiable {
    case fountain = "Fountain", pencil = "Pencil", monoline = "Monoline", watercolor = "Watercolor", crayon = "Crayon", marker = "Marker", eraser = "Eraser"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .fountain: return "pencil.tip.crop.circle"
        case .pencil: return "pencil"
        case .monoline: return "line.diagonal"
        case .watercolor: return "drop.halffull"
        case .crayon: return "scribble.variable"
        case .marker: return "highlighter"
        case .eraser: return "eraser"
        }
    }
    func pkTool(color: UIColor, width: CGFloat) -> any PKTool {
        switch self {
        case .fountain: return PKInkingTool(.fountainPen, color: color, width: width)
        case .pencil: return PKInkingTool(.pencil, color: color, width: width)
        case .monoline: return PKInkingTool(.monoline, color: color, width: width)
        case .watercolor: return PKInkingTool(.watercolor, color: color, width: width)
        case .crayon: return PKInkingTool(.crayon, color: color, width: width)
        case .marker: return PKInkingTool(.marker, color: color.withAlphaComponent(0.65), width: width)
        case .eraser: return PKEraserTool(.bitmap, width: max(4, width))
        }
    }
}

@MainActor
final class ArtworkStore: ObservableObject {
    @Published var layers: [ArtworkLayer]
    @Published var selectedLayerID: UUID
    @Published var brush: ArtBrush = .fountain
    @Published var brushSize: CGFloat = 4
    @Published var brushColor: UIColor = .black
    @Published var restSafe = true
    @Published var status = "Layered artwork autosaves on this iPad"
    @Published var zoom: CGFloat = 1
    weak var canvasHost: LayeredArtworkHost?

    private var saveJob: DispatchWorkItem?
    private let fileURL: URL
    private let artworkDirectory: URL

    init() {
        artworkDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InfiniCanvas", isDirectory: true)
            .appendingPathComponent("Artwork", isDirectory: true)
        fileURL = artworkDirectory.appendingPathComponent("artwork.json")
        try? FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: fileURL),
           let document = try? JSONDecoder().decode(ArtworkDocument.self, from: data),
           !document.layers.isEmpty {
            layers = document.layers
            selectedLayerID = document.layers.contains(where: { $0.id == document.selected })
                ? document.selected : document.layers[0].id
        } else {
            let layer = ArtworkLayer(name: "Sketch")
            layers = [layer]
            selectedLayerID = layer.id
        }
    }

    func drawing(for layer: ArtworkLayer) -> PKDrawing {
        (try? PKDrawing(data: layer.drawing)) ?? PKDrawing()
    }

    func drawingChanged(_ newDrawing: PKDrawing, for id: UUID) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[i].drawing = newDrawing.dataRepresentation()
        scheduleSave()
    }
    private func scheduleSave() {
        saveJob?.cancel()
        let job = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveJob = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: job)
    }
    func saveNow() {
        saveJob?.cancel()
        do {
            let model = ArtworkDocument(layers: layers, selected: selectedLayerID)
            try JSONEncoder().encode(model).write(to: fileURL, options: .atomic)
            status = "Artwork saved"
        } catch { status = "Artwork save failed—retry" }
    }
    func addLayer() {
        let layer = ArtworkLayer(name: "Layer \(layers.count + 1)")
        layers.append(layer)
        selectedLayerID = layer.id
        saveNow()
    }
    func removeLayer(_ id: UUID) {
        guard layers.count > 1 else { status = "Keep at least one layer"; return }
        layers.removeAll { $0.id == id }
        if selectedLayerID == id { selectedLayerID = layers.last!.id }
        saveNow()
    }
    func moveLayer(from offsets: IndexSet, to destination: Int) {
        layers.move(fromOffsets: offsets, toOffset: destination)
        saveNow()
    }
    func duplicateLayer(_ id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        var copy = layers[index]
        copy.id = UUID()
        copy.name = "\(copy.name) copy"
        layers.insert(copy, at: min(index + 1, layers.count))
        selectedLayerID = copy.id
        saveNow()
    }
    func selectLayer(_ id: UUID) {
        guard let layer = layers.first(where: { $0.id == id }), !layer.isLocked && layer.isVisible else { return }
        selectedLayerID = id
        saveNow()
    }
    func updateLayer(_ id: UUID, opacity: Double? = nil, isVisible: Bool? = nil, isLocked: Bool? = nil) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        if let opacity { layers[index].opacity = opacity }
        if let isVisible { layers[index].isVisible = isVisible }
        if let isLocked { layers[index].isLocked = isLocked }
        saveNow()
    }
    func undo() { canvasHost?.activeCanvas?.undoManager?.undo() }
    func redo() { canvasHost?.activeCanvas?.undoManager?.redo() }

    func exportPNG() -> URL? {
        saveNow()
        // Fixed 2048×2048 art sheet. The big NOTES canvas remains separately zoomable.
        let rect = CGRect(x: 0, y: 0, width: 2048, height: 2048)
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        let output = renderer.image { ctx in
            UIColor.white.setFill(); ctx.fill(rect)
            for layer in layers where layer.isVisible {
                let image = drawing(for: layer).image(from: rect, scale: 1)
                image.draw(in: rect, blendMode: .normal, alpha: layer.opacity)
            }
        }
        guard let data = output.pngData() else { return nil }
        let path = artworkDirectory.appendingPathComponent("InfiniCanvas-Art-\(Int(Date().timeIntervalSince1970)).png")
        do { try data.write(to: path, options: .atomic); return path }
        catch { status = "PNG export failed"; return nil }
    }
}

struct ArtStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var art = ArtworkStore()
    @State private var showLayers = true
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var showBrushes = false
    @State private var showDeleteConfirm = false
    @State private var pendingDeletion: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { art.saveNow(); dismiss() } label: {
                    Label("Notes", systemImage: "chevron.left").font(.subheadline.weight(.semibold))
                }
                Text("Art Studio").font(.headline)
                Spacer()
                Button { art.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .accessibilityLabel("Undo art stroke")
                Button { art.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .accessibilityLabel("Redo art stroke")
                Button { art.restSafe.toggle() } label: {
                    Label(art.restSafe ? "Palm lock" : "Navigate", systemImage: art.restSafe ? "hand.raised.fill" : "hand.draw")
                }
                .font(.caption.weight(.medium))
                Button { showLayers.toggle() } label: { Image(systemName: "square.3.layers.3d") }
                    .accessibilityLabel("Show or hide layers")
                Button {
                    shareURL = art.exportPNG()
                    showShare = shareURL != nil
                } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Export flattened PNG")
            }
            .buttonStyle(.bordered)
            .padding(11)
            .background(.regularMaterial)

            HStack(spacing: 0) {
                LayeredArtworkCanvas(art: art)
                    .background(Color.white)
                    .clipped()
                if showLayers {
                    layerPanel
                        .frame(width: 230)
                        .background(Color(uiColor: .secondarySystemBackground))
                }
            }
            HStack(spacing: 10) {
                Menu {
                    ForEach(ArtBrush.allCases) { brush in
                        Button { art.brush = brush } label: { Label(brush.rawValue, systemImage: brush.icon) }
                    }
                } label: { Label(art.brush.rawValue, systemImage: art.brush.icon) }
                    .buttonStyle(.borderedProminent)
                ColorPicker("Color", selection: Binding(
                    get: { Color(uiColor: art.brushColor) },
                    set: { art.brushColor = UIColor($0) }), supportsOpacity: false)
                    .labelsHidden().frame(width: 42)
                Slider(value: Binding(get: { Double(art.brushSize) },
                    set: { art.brushSize = CGFloat($0) }), in: 0.5...80)
                    .frame(maxWidth: 190)
                Text(String(format: "%.1f", Double(art.brushSize)))
                    .font(.caption.monospacedDigit())
                Spacer(minLength: 0)
                Text(art.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(11)
            .background(.regularMaterial)
        }
        .onDisappear { art.saveNow() }
        .sheet(isPresented: $showShare) {
            if let shareURL { SystemShareSheet(items: [shareURL]) }
        }
        .confirmationDialog("Delete layer?", isPresented: $showDeleteConfirm) {
            Button("Delete layer", role: .destructive) {
                if let pendingDeletion { art.removeLayer(pendingDeletion) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        }
    }

    private var layerPanel: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Layers").font(.headline)
                Spacer()
                Button { art.addLayer() } label: { Image(systemName: "plus.circle.fill") }
                    .accessibilityLabel("New layer")
            }.padding(.horizontal, 12).padding(.top, 14)
            List {
                ForEach(art.layers.reversed()) { layer in
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Button { art.selectLayer(layer.id) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(layer.name).lineLimit(1)
                                    if layer.id == art.selectedLayerID {
                                        Text("Editing").font(.caption2).foregroundStyle(.teal)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            Button { art.updateLayer(layer.id, isVisible: !layer.isVisible) } label: {
                                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                            }.accessibilityLabel(layer.isVisible ? "Hide layer" : "Show layer")
                            Button { art.updateLayer(layer.id, isLocked: !layer.isLocked) } label: {
                                Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                            }.accessibilityLabel(layer.isLocked ? "Unlock layer" : "Lock layer")
                        }
                        Slider(value: Binding(
                            get: { art.layers.first(where: { $0.id == layer.id })?.opacity ?? 1 },
                            set: { art.updateLayer(layer.id, opacity: $0) }), in: 0...1)
                        Menu {
                            Button("Duplicate layer", systemImage: "square.on.square") { art.duplicateLayer(layer.id) }
                            Button("Remove layer", systemImage: "trash", role: .destructive) {
                                pendingDeletion = layer.id; showDeleteConfirm = true
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(layer.id == art.selectedLayerID ? Color.teal.opacity(0.1) : Color.clear)
                }
                .onMove { from, to in
                    // The list is shown top-first; translate drag to bottom-first model.
                    let n = art.layers.count
                    let reversed = Array(art.layers.reversed())
                    var working = reversed
                    working.move(fromOffsets: from, toOffset: to)
                    art.layers = Array(working.reversed())
                    if art.layers.count == n { art.saveNow() }
                }
            }
            .listStyle(.plain)
            Text("Reorder with Edit, hide or lock a layer, or change its opacity.")
                .font(.caption2).foregroundStyle(.secondary).padding(10)
        }
    }
}

struct LayeredArtworkCanvas: UIViewRepresentable {
    @ObservedObject var art: ArtworkStore
    func makeCoordinator() -> Coordinator { Coordinator(art: art) }
    func makeUIView(context: Context) -> LayeredArtworkHost {
        let host = LayeredArtworkHost()
        context.coordinator.host = host
        art.canvasHost = host
        host.reconcile(art: art, coordinator: context.coordinator)
        return host
    }
    func updateUIView(_ host: LayeredArtworkHost, context: Context) {
        host.reconcile(art: art, coordinator: context.coordinator)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        weak var host: LayeredArtworkHost?
        weak var art: ArtworkStore?
        var suppress = false
        init(art: ArtworkStore) { self.art = art }
        func canvasViewDrawingDidChange(_ view: PKCanvasView) {
            guard !suppress, let host,
                  let layerID = host.canvasToLayer[ObjectIdentifier(view)] else { return }
            let drawing = view.drawing
            Task { @MainActor [weak art] in
                art?.drawingChanged(drawing, for: layerID)
            }
        }
        func scrollViewDidScroll(_ view: UIScrollView) { host?.syncViewport(from: view) }
        func scrollViewDidZoom(_ view: UIScrollView) { host?.syncViewport(from: view) }
    }
}

final class LayeredArtworkHost: UIView {
    var canvases: [UUID: PKCanvasView] = [:]
    var canvasToLayer: [ObjectIdentifier: UUID] = [:]
    var activeCanvas: PKCanvasView?
    private var syncing = false
    private var restSafe = true
    private var pinchActivated = false
    private var pinchInitialDistance: CGFloat = 0
    private var pinchStartDistance: CGFloat = 1
    private var pinchStartZoom: CGFloat = 1
    private var lastToolSignature = ""
    private let paperSize = CGSize(width: 2048, height: 2048)

    override init(frame: CGRect) {
        super.init(frame: frame)
        let gesture = UIPinchGestureRecognizer(target: self, action: #selector(deliberatePinch(_:)))
        gesture.cancelsTouchesInView = false
        addGestureRecognizer(gesture)
    }
    required init?(coder: NSCoder) { fatalError("Storyboards are not used") }

    @objc private func deliberatePinch(_ gesture: UIPinchGestureRecognizer) {
        guard restSafe, let canvas = activeCanvas else { return }
        switch gesture.state {
        case .began:
            pinchInitialDistance = 0
            pinchActivated = false
        case .changed:
            guard gesture.numberOfTouches >= 2 else { return }
            let first = gesture.location(ofTouch: 0, in: self)
            let second = gesture.location(ofTouch: 1, in: self)
            let distance = hypot(first.x - second.x, first.y - second.y)
            if pinchInitialDistance == 0 { pinchInitialDistance = distance }
            if !pinchActivated {
                guard distance >= 150 && abs(distance - pinchInitialDistance) >= 35 else { return }
                pinchStartDistance = distance
                pinchStartZoom = canvas.zoomScale
                pinchActivated = true
                return
            }
            let scale = max(canvas.minimumZoomScale, min(canvas.maximumZoomScale,
                            pinchStartZoom * distance / max(1, pinchStartDistance)))
            let touch = gesture.location(in: self)
            let before = max(0.001, canvas.zoomScale)
            let content = CGPoint(x: (canvas.contentOffset.x + touch.x) / before,
                                  y: (canvas.contentOffset.y + touch.y) / before)
            canvas.setZoomScale(scale, animated: false)
            canvas.setContentOffset(CGPoint(x: content.x * scale - touch.x,
                                            y: content.y * scale - touch.y), animated: false)
            syncViewport(from: canvas)
        case .ended, .failed, .cancelled:
            pinchInitialDistance = 0
            pinchActivated = false
        default: break
        }
    }

    func reconcile(art: ArtworkStore, coordinator: LayeredArtworkCanvas.Coordinator) {
        restSafe = art.restSafe
        let wanted = Set(art.layers.map(\.id))
        for (id, canvas) in canvases where !wanted.contains(id) {
            canvas.removeFromSuperview()
            canvasToLayer.removeValue(forKey: ObjectIdentifier(canvas))
            canvases.removeValue(forKey: id)
        }
        for layer in art.layers where canvases[layer.id] == nil {
            let canvas = PKCanvasView(frame: bounds)
            canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            canvas.backgroundColor = .clear
            canvas.isOpaque = false
            canvas.drawingPolicy = .pencilOnly
            canvas.minimumZoomScale = 0.1
            canvas.maximumZoomScale = 24
            canvas.contentSize = paperSize
            canvas.panGestureRecognizer.minimumNumberOfTouches = 2
            coordinator.suppress = true
            canvas.drawing = art.drawing(for: layer)
            coordinator.suppress = false
            canvas.delegate = coordinator
            addSubview(canvas)
            canvases[layer.id] = canvas
            canvasToLayer[ObjectIdentifier(canvas)] = layer.id
            if let reference = activeCanvas {
                canvas.setZoomScale(reference.zoomScale, animated: false)
                canvas.contentOffset = reference.contentOffset
            }
        }
        // Keep correct painter order; layers are bottom-to-top in the model.
        let toolSignature = "\(art.selectedLayerID.uuidString)|\(art.brush.rawValue)|\(art.brushSize)|\(art.brushColor.description)"
        let toolChanged = toolSignature != lastToolSignature
        lastToolSignature = toolSignature
        activeCanvas = nil
        for layer in art.layers {
            guard let canvas = canvases[layer.id] else { continue }
            bringSubviewToFront(canvas)
            canvas.alpha = CGFloat(layer.opacity)
            canvas.isHidden = !layer.isVisible
            let editing = layer.id == art.selectedLayerID && !layer.isLocked && layer.isVisible
            canvas.isUserInteractionEnabled = editing
            canvas.isScrollEnabled = editing && !art.restSafe
            if editing {
                // Don't reset an in-progress stroke during ObservableObject updates.
                if toolChanged { canvas.tool = art.brush.pkTool(color: art.brushColor, width: art.brushSize) }
                activeCanvas = canvas
            }
        }
    }
    func syncViewport(from scroll: UIScrollView) {
        guard !syncing, let selected = activeCanvas, scroll === selected else { return }
        syncing = true
        for view in canvases.values where view !== selected {
            if abs(view.zoomScale - selected.zoomScale) > 0.001 {
                view.setZoomScale(selected.zoomScale, animated: false)
            }
            view.contentOffset = selected.contentOffset
        }
        syncing = false
    }
}
