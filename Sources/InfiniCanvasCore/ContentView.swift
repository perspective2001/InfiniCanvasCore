import SwiftUI
import UIKit
import PencilKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: CanvasStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("InfiniCanvas.targetConversationURL") private var targetChatURL = ""
    @AppStorage("InfiniCanvas.showAreaPins") private var showAreaPins = true
    @State private var showLibrary = false
    @State private var showSettings = false
    @State private var showAddArea = false
    @State private var newAreaName = ""
    @State private var focusMode = false
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var importing = false
    @State private var selectedImportURL: URL?
    @State private var confirmRestore = false
    @State private var selectedRevision: URL?
    @State private var showTextEditor = false
    @State private var editingNote: TypedNote?
    @State private var textDraft = ""
    @State private var confirmRevision = false
    @State private var showLectures = false
    @State private var selectedAutoBackup: URL?
    @State private var confirmAutoBackup = false
    @State private var widthPanelExpanded = false
    @State private var widthDragStart: CGFloat? = nil
    @State private var showEraserOptions = false
    @State private var showHighlighterOptions = false
    @State private var showArtStudio = false
    @State private var showTopBar = true
    @State private var paperOnly = false
    @State private var showFocusChoices = false

    private let teal = Color(red: 0.07, green: 0.40, blue: 0.43)
    private let swatches: [(String, UIColor)] = [
        ("Ink", UIColor(red: 0.10, green: 0.16, blue: 0.20, alpha: 1)),
        ("Blue", UIColor(red: 0.17, green: 0.36, blue: 0.76, alpha: 1)),
        ("Teal", UIColor(red: 0.06, green: 0.52, blue: 0.53, alpha: 1)),
        ("Red", UIColor(red: 0.83, green: 0.24, blue: 0.25, alpha: 1)),
        ("Gold", UIColor(red: 0.85, green: 0.53, blue: 0.11, alpha: 1)),
        ("Purple", UIColor(red: 0.48, green: 0.31, blue: 0.69, alpha: 1))
    ]

    var body: some View {
        ZStack(alignment: .top) {
            PencilCanvas(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if store.tool == .capture { LassoOverlay(store: store) }
            if store.tool == .marker && store.fixedHighlighter { FixedHighlighterOverlay(store: store) }
            if let focus = store.focusedArea { isolatedAreaShade(focus).allowsHitTesting(false) }
            if store.tool != .capture && !focusMode && store.zoom > 0.5 { textNoteCards
                .allowsHitTesting(!store.restSafe)
            }
            if showAreaPins && store.zoom <= 0.55 && !focusMode && store.tool != .capture {
                semanticOverview
                    .allowsHitTesting(!store.restSafe)
            } else if showAreaPins && store.zoom <= 0.85 && !focusMode && store.tool != .capture {
                areaPins
                    .allowsHitTesting(!store.restSafe)
            }
            if !paperOnly {
                VStack(spacing: 0) {
                    if focusMode {
                        focusHeader
                    } else {
                        if showTopBar {
                            topChromeGrip
                            header
                        } else {
                            // Compact mode puts the actual tools almost flush to the top.
                            // The thin transparent grip still accepts a deliberate down swipe.
                            topChromeGrip.frame(height: 10)
                        }
                        toolShelf
                    }
                    Spacer(minLength: 0)
                    if store.tool == .capture && !focusMode { lassoActions }
                    if !focusMode { footer }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.991, green: 0.984, blue: 0.961))
        .overlay(alignment: .leading) {
            if !paperOnly { edgeHistoryControl(isUndo: true) }
        }
        .overlay(alignment: .trailing) {
            if !paperOnly { edgeHistoryControl(isUndo: false) }
        }
        .overlay(alignment: .topTrailing) { sideFocusHandle.padding(.top, 125) }
        .overlay(alignment: .top) {
            if paperOnly { topChromeGrip }
        }
        .overlay(alignment: .topTrailing) {
            if widthPanelExpanded && !paperOnly && !focusMode {
                floatingWidthPanel
                    .padding(.top, showTopBar ? 105 : 38)
                    .padding(.trailing, 20)
                    .zIndex(99)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.65, anchor: .topTrailing).combined(with: .opacity),
                        removal: .scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity)
                    ))
            }
        }
        .tint(teal)
        .fullScreenCover(isPresented: $showArtStudio) { ArtStudioView() }
        .sheet(isPresented: $showLibrary) { ClipLibraryView(store: store, onOpenChat: openSpecificChat) }
        .sheet(isPresented: $showLectures) { LectureLibraryView(store: store) }
        .sheet(isPresented: $store.organizationPreview) { OrganizationPreviewView(store: store) }
        .sheet(isPresented: $showSettings) {
            ChatDestinationView(store: store, conversationURL: $targetChatURL, showAreaPins: $showAreaPins)
        }
        .sheet(isPresented: $showTextEditor) {
            NavigationStack {
                VStack {
                    TextEditor(text: $textDraft)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    Spacer()
                }
                .padding(18)
                .background(Color(white: 0.97))
                .navigationTitle(editingNote == nil ? "New typed note" : "Edit typed note")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showTextEditor = false; editingNote = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let value = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let note = editingNote { store.editTextNote(note, text: value) }
                            else if !value.isEmpty { store.addTextNote(value) }
                            editingNote = nil; showTextEditor = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL { SystemShareSheet(items: [url]) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { selectedImportURL = url; confirmRestore = true }
        }
        .confirmationDialog("Replace current canvas from backup?", isPresented: $confirmRestore) {
            Button("Restore complete backup", role: .destructive) {
                if let url = selectedImportURL { _ = store.restoreCompleteBackup(url) }
                selectedImportURL = nil
            }
            Button("Cancel", role: .cancel) { selectedImportURL = nil }
        } message: {
            Text("A recovery copy of your existing ink will be retained. Imported areas and clips replace their current index.")
        }
        .confirmationDialog("Restore a complete automatic snapshot?", isPresented: $confirmAutoBackup) {
            Button("Restore this snapshot", role: .destructive) {
                if let url = selectedAutoBackup { _ = store.restoreAutomaticBackup(url) }
                selectedAutoBackup = nil
            }
            Button("Cancel", role: .cancel) { selectedAutoBackup = nil }
        } message: { Text("This snapshot replaces the current notes, clips, labels and lecture audio. Your current drawing receives a recovery copy first.") }
        .confirmationDialog("Restore an earlier drawing revision?", isPresented: $confirmRevision) {
            Button("Restore earlier ink", role: .destructive) {
                if let url = selectedRevision { _ = store.restoreRevision(url) }
                selectedRevision = nil
            }
            Button("Cancel", role: .cancel) { selectedRevision = nil }
        } message: { Text("Your current ink is copied to a recovery file before restoration.") }
        .alert("Name this canvas area", isPresented: $showAddArea) {
            TextField("e.g. PSYC 1010 · Learning", text: $newAreaName)
            Button("Add marker") {
                let title = newAreaName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { store.addArea(title) }
                newAreaName = ""
            }
            Button("Cancel", role: .cancel) { newAreaName = "" }
        } message: {
            Text("This is a named position inside the same canvas. No separate page is created.")
        }
        .onDisappear { store.saveImmediately() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.saveImmediately() }
        }
    }

    // Invisible extreme-right strip: only an intentional double tap toggles
    // paper-only mode. Both Apple Pencil and finger are accepted; no tap button
    // or bright green affordance obscures the drawing.
    private var sideFocusHandle: some View {
        FingerDoubleTapTarget {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                paperOnly.toggle()
                widthPanelExpanded = false
            }
        }
        .frame(width: 32, height: 120)
        .contentShape(Rectangle())
        .accessibilityLabel("Double tap extreme right edge to toggle paper-only mode")
    }

    private func edgeHistoryControl(isUndo: Bool) -> some View {
        Button {
            if isUndo { store.undo() } else { store.redo() }
        } label: {
            Image(systemName: isUndo ? "arrow.uturn.backward" : "arrow.uturn.forward")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 38, height: 45)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(CanvasGlassSurface(cornerRadius: 15))
        .padding(isUndo ? .leading : .trailing, 2)
        .keyboardShortcut("z", modifiers: isUndo ? .command : [.command, .shift])
        .accessibilityLabel(isUndo ? "Undo" : "Redo")
        .accessibilityHint("Requires a deliberate tap; hidden in paper-only mode")
    }

    // Always-present top handle. Swipe UP to tuck the header away, DOWN to reveal.
    // Tapping it also toggles the header, providing a reliable fallback if a swipe
    // is intercepted by iPadOS or Swift Playgrounds.
    private var topChromeGrip: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
            // No coloured tab remains visible when the menus are hidden.
            Color.clear.frame(width: 52, height: 6).allowsHitTesting(false)
        }
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.20)) {
                if paperOnly {
                    paperOnly = false
                    focusMode = false
                    showTopBar = true
                } else {
                    showTopBar.toggle()
                }
            }
        }
        .highPriorityGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    let dy = value.translation.height
                    guard abs(dy) > 22 && abs(dy) > abs(value.translation.width) * 1.2 else { return }
                    withAnimation(.easeInOut(duration: 0.20)) {
                        if dy > 0 {
                            paperOnly = false
                            focusMode = false
                            showTopBar = true
                        } else {
                            paperOnly = false
                            showTopBar = false
                        }
                    }
                }
        )
        .background(Color.clear)
        .accessibilityLabel("Top controls grip")
        .accessibilityHint("Swipe up to hide the command bar, swipe down to reveal it, or tap to toggle")
    }

    private func isolatedAreaShade(_ area: CanvasArea) -> some View {
        GeometryReader { geo in
            let center = store.screenPoint(for: area)
            let w = CGFloat(area.width ?? 2400) * store.zoom
            let h = CGFloat(area.height ?? 1600) * store.zoom
            let focus = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
            Path { path in
                path.addRect(CGRect(origin: .zero, size: geo.size))
                path.addRoundedRect(in: focus, cornerSize: CGSize(width: 10, height: 10))
            }
            .fill(Color(uiColor: CanvasStore.paperBackground(store.paper)).opacity(0.97), style: FillStyle(eoFill: true))
            .overlay {
                Path { path in path.addRoundedRect(in: focus, cornerSize: CGSize(width: 10, height: 10)) }
                    .stroke(teal.opacity(0.4), lineWidth: 1)
            }
        }
        .ignoresSafeArea()
    }

    // A quiet, stable command bar: Undo and Redo never disappear into scrolling tools.
    private var historyButtons: some View {
        HStack(spacing: 4) {
            Button { store.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 37, height: 40)
            }
            .keyboardShortcut("z", modifiers: .command)
            .accessibilityLabel("Undo last stroke")
            .accessibilityHint("Reverses the last completed pencil stroke or edit")
            Button { store.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 37, height: 40)
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .accessibilityLabel("Redo")
            .accessibilityHint("Restores the last undone stroke")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(teal)
        .padding(3)
        .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black.opacity(0.05)))
    }

    private var palmModeButton: some View {
        Button { store.restSafe.toggle() } label: {
            Label(store.restSafe ? "RestSafe" : "Navigate", systemImage: store.restSafe ? "hand.raised.fill" : "hand.draw")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 5)
                .frame(minHeight: 40)
        }
        .buttonStyle(.borderedProminent)
        .tint(store.restSafe ? teal : .orange)
        .accessibilityHint("RestSafe prevents unintended palm and finger navigation; tap to switch to two-finger navigation")
    }

    private var header: some View {
        HStack(spacing: 9) {
            HStack(spacing: 9) {
                Button { showArtStudio = true } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "infinity")
                            .font(.system(size: 23, weight: .medium))
                        Text("Infini Canvas")
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "paintpalette")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(teal)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open the separately saved layered Art Studio")
            }
            Spacer(minLength: 4)
            palmModeButton
            Menu {
                Button("Overview · 14%", systemImage: "square.dashed") { store.zoomToOverview() }
                Button("Writing · 100%", systemImage: "pencil") { store.zoomToWriting() }
                Button("Zoom out further", systemImage: "minus.magnifyingglass") { store.zoomBy(0.4) }
                Button("Zoom in", systemImage: "plus.magnifyingglass") { store.zoomBy(2.5) }
                Button("Exact 1000% zoom · native maximum", systemImage: "plus.viewfinder") { store.zoomTo(10) }
            } label: {
                Image(systemName: "square.dashed.inset.filled")
                    .frame(width: 36, height: 40)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Zoom to overview")
            Button { showLibrary = true } label: {
                Image(systemName: "square.stack.3d.up")
                    .frame(width: 36, height: 40)
                    .overlay(alignment: .topTrailing) {
                        if !store.dueClips.isEmpty {
                            Circle().fill(.orange).frame(width: 7, height: 7).offset(x: -1, y: 3)
                        }
                    }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open clip and study library")
            if store.focusedArea != nil {
                Button { store.revealAllAreas() } label: {
                    Label("Reveal", systemImage: "eye")
                        .font(.caption.weight(.semibold))
                }.buttonStyle(.bordered)
            }
            moreMenu
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .modifier(CanvasGlassSurface(cornerRadius: 20))
    }

    // Uncommon actions belong in menus, not between the Pencil and undo controls.
    private var moreMenu: some View {
        Menu {
            Button("Auto-label nearby handwriting", systemImage: "text.magnifyingglass") { store.autoNameAndAddArea() }
            Button("Manually name area", systemImage: "mappin.and.ellipse") { showAddArea = true }
            Menu("Isolate one area", systemImage: "eye") {
                Button("Show all writing", systemImage: "eye.fill") { store.revealAllAreas() }
                ForEach(store.activeAreas) { area in
                    Button(area.title) { store.focusOnArea(area) }
                }
            }
            Button("Open layered Art Studio", systemImage: "paintpalette") { showArtStudio = true }
            Button("New typed note", systemImage: "textformat") { openTextEditor() }
            Button("Organize saved clips", systemImage: "square.grid.2x2") { store.prepareOrganization() }
            Button("Lecture recordings", systemImage: "waveform") { showLectures = true }
            if store.recording {
                Button("Mark lecture moment", systemImage: "bookmark") { store.addLectureMark() }
                Button("Stop recording", systemImage: "stop.circle") { store.endLectureRecording() }
            } else {
                Button("Start lecture recording", systemImage: "record.circle") { store.beginLectureRecording() }
            }
            Divider()
            Menu("Paper style", systemImage: store.paper.symbol) {
                ForEach(PaperStyle.allCases) { style in
                    Button { store.paper = style } label: {
                        Label(style.rawValue, systemImage: style.symbol)
                    }
                }
            }
            Button("Toggle ruler", systemImage: "ruler") { store.toggleRuler() }
            Button("Apple Pencil palette", systemImage: "paintpalette") { store.showSystemTools() }
            Button("Minimal writing controls", systemImage: "arrow.up.left.and.arrow.down.right") { focusMode = true }
            Button("Hide top command bar", systemImage: "chevron.up") { showTopBar = false }
            Button("Jump to most recent handwriting", systemImage: "location.magnifyingglass") { store.goToLastInk() }
            Button("Hide all menus", systemImage: "rectangle.dashed") { paperOnly = true }
            if !store.organizedUndo.isEmpty {
                Button("Undo last organization", systemImage: "arrow.uturn.backward") { store.undoOrganization() }
            }
            Divider()
            Button("ChatGPT destination & preferences", systemImage: "gearshape") { showSettings = true }
            Button("Export complete backup", systemImage: "square.and.arrow.up") { shareBackup() }
            Button("Import complete backup", systemImage: "square.and.arrow.down") { importing = true }
            if !store.automaticBackupFiles.isEmpty {
                Menu("Restore automatic backup", systemImage: "externaldrive") {
                    ForEach(store.automaticBackupFiles, id: \.self) { url in
                        Button(url.deletingPathExtension().lastPathComponent) {
                            selectedAutoBackup = url; confirmAutoBackup = true
                        }
                    }
                }
            }
            if !store.revisionFiles.isEmpty {
                Menu("Restore earlier ink", systemImage: "clock.arrow.circlepath") {
                    ForEach(store.revisionFiles, id: \.self) { url in
                        Button(url.deletingPathExtension().lastPathComponent) {
                            selectedRevision = url; confirmRevision = true
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 19, weight: .medium))
                .frame(width: 38, height: 40)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("More actions and settings")
    }

    private var focusHeader: some View {
        HStack(spacing: 10) {
            palmModeButton
            Spacer(minLength: 0)
            Label(store.isSaved ? "Saved" : "Saving", systemImage: store.isSaved ? "checkmark.circle.fill" : "clock")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Button { focusMode = false } label: {
                Image(systemName: "rectangle.expand.vertical")
                    .frame(width: 36, height: 40)
            }
            .accessibilityLabel("Show drawing tools")
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(.regularMaterial)
    }

    private var toolShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        showTopBar.toggle()
                    }
                } label: {
                    Image(systemName: showTopBar ? "chevron.up" : "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 46)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showTopBar ? "Compact top controls" : "Reveal complete command bar")
                ForEach(CanvasTool.allCases) { tool in
                    Button {
                        if tool == .pen {
                            // First press always restores the ordinary Apple pen, not
                            // the persisted Fountain profile. Press again for styles.
                            if store.tool == .pen && store.penProfile == .fluid {
                                widthPanelExpanded = true
                            } else {
                                store.tool = .pen
                                store.penProfile = .fluid
                            }
                        } else {
                            store.tool = tool
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tool.symbol).font(.system(size: 20, weight: .medium))
                            Text(tool == .pen && store.tool == .pen && store.penProfile == .fountain ? "Fountain" :
                                 tool == .pen && store.tool == .pen && store.penProfile == .monoline ? "Monoline" :
                                 tool.rawValue).font(.system(size: 10, weight: .medium))
                        }
                        .frame(minWidth: 57, minHeight: 48)
                        .foregroundStyle(store.tool == tool ? teal : Color.primary)
                        .background(store.tool == tool ? teal.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                        .modifier(CanvasGlassSurface(cornerRadius: 11))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tool.rawValue)
                }
                Rectangle().fill(.black.opacity(0.09)).frame(width: 1, height: 28).padding(.horizontal, 7)
                ForEach(swatches.indices.prefix(5), id: \.self) { i in
                    Button {
                        store.inkColor = swatches[i].1
                        if store.tool == .eraser || store.tool == .capture { store.tool = .pen }
                    } label: {
                        Circle()
                            .fill(Color(uiColor: swatches[i].1))
                            .frame(width: 22, height: 22)
                            .padding(5)
                            .overlay(Circle().stroke(teal.opacity(0.9), lineWidth: store.inkColor.isEqual(swatches[i].1) ? 2 : 0).padding(1))
                            .frame(width: 36, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ink color: \(swatches[i].0)")
                }
                ColorPicker("More colors", selection: Binding(
                    get: { Color(uiColor: store.inkColor) },
                    set: { store.inkColor = UIColor($0) }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 40)
                Rectangle().fill(.black.opacity(0.09)).frame(width: 1, height: 28).padding(.horizontal, 7)
                if store.tool == .marker {
                    Button { showHighlighterOptions = true } label: {
                        Label(store.fixedHighlighter ? "Vertical nib" : "Native marker", systemImage: "highlighter")
                            .font(.caption.weight(.medium))
                            .frame(minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                    .popover(isPresented: $showHighlighterOptions, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Highlighter tip").font(.headline)
                            Toggle("Lock nib vertically", isOn: $store.fixedHighlighter)
                            Text("Fixed nib records each stroke as editable PencilKit ink. Native mode follows Apple's marker rendering and Pencil tilt.")
                                .font(.caption).foregroundStyle(.secondary)
                            if store.fixedHighlighter {
                                Text("Nib height · \(Int(store.markerHeight)) pt").font(.caption)
                                Slider(value: Binding(get: { Double(store.markerHeight) },
                                    set: { store.markerHeight = CGFloat($0) }), in: 8...45)
                                Text("Nib width · \(Int(store.markerWidth)) pt").font(.caption)
                                Slider(value: Binding(get: { Double(store.markerWidth) },
                                    set: { store.markerWidth = CGFloat($0) }), in: 2...15)
                            }
                        }
                        .padding(18).frame(width: 315)
                    }
                }
                if store.tool == .eraser {
                    Button { showEraserOptions = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "eraser")
                            Text(store.eraserPrecision == .detail ? "Detail" : "Stroke")
                        }.frame(minWidth: 78, minHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .popover(isPresented: $showEraserOptions, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("Eraser").font(.headline)
                            Picker("Erase mode", selection: $store.eraserPrecision) {
                                ForEach(EraserPrecision.allCases) { precision in
                                    Text(precision.rawValue).tag(precision)
                                }
                            }.pickerStyle(.segmented)
                            Text(store.eraserPrecision == .detail ? "Remove small parts of a stroke" : "Erase entire strokes in one pass")
                                .font(.caption).foregroundStyle(.secondary)
                            Slider(value: Binding(get: { Double(store.eraserWidth) },
                                set: { store.eraserWidth = CGFloat($0) }), in: 3...60)
                            Text("Eraser size: \(Int(store.eraserWidth))").font(.caption)
                        }.padding(18).frame(width: 290)
                    }
                }
                if store.mode == .art {
                    Menu {
                        Button("Detail brush · 0.8", systemImage: "paintbrush.pointed") { store.tool = .pen; store.strokeWidth = 0.8 }
                        Button("Inking brush · 3", systemImage: "pencil.tip") { store.tool = .pen; store.strokeWidth = 3 }
                        Button("Painter brush · 15", systemImage: "paintbrush") { store.tool = .pencil; store.strokeWidth = 15 }
                        Button("Broad brush · 45", systemImage: "paintbrush.fill") { store.tool = .marker; store.strokeWidth = 11 }
                    } label: {
                        Label("Brushes", systemImage: "paintbrush.pointed.fill")
                    }.buttonStyle(.bordered)
                }
                penWidthTrigger
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .modifier(CanvasGlassSurface(cornerRadius: 20))
    }

    // Swipe upward from the compact width icon to reveal an expanding, directly
    // draggable vertical width slider. The same gesture can immediately change
    // pen width without lifting the Pencil. A tap is also supported.
    private var penWidthTrigger: some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.79)) {
                widthPanelExpanded.toggle()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "lineweight")
                    .font(.system(size: 18, weight: .medium))
                Text(String(format: "%.1f", Double(store.strokeWidth)))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 35, alignment: .trailing)
            }
            .frame(width: 84, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Pen size: \(String(format: "%.1f", Double(store.strokeWidth)))")
        .accessibilityHint("Swipe up to expand size slider, keep dragging to resize, or tap")
        .highPriorityGesture(
            DragGesture(minimumDistance: 7)
                .onChanged { value in
                    if value.translation.height < -12 {
                        if widthDragStart == nil {
                            widthDragStart = store.strokeWidth
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.77)) {
                                widthPanelExpanded = true
                            }
                        }
                        let baseline = widthDragStart ?? store.strokeWidth
                        let maxSize: CGFloat = store.mode == .art ? 80 : 18
                        store.strokeWidth = min(maxSize, max(0.4,
                            baseline + (-value.translation.height - 12) * 0.075))
                    }
                }
                .onEnded { value in
                    widthDragStart = nil
                    if value.translation.height > 48 {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                            widthPanelExpanded = false
                        }
                    }
                }
        )
    }

    private var floatingWidthPanel: some View {
        VStack(spacing: 11) {
            Capsule()
                .fill(teal.opacity(0.55))
                .frame(width: 43, height: 5)
                .frame(height: 23)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                    if value.translation.height > 30 {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            widthPanelExpanded = false
                        }
                    }
                })
                .accessibilityLabel("Swipe down to close pen size")
            HStack(spacing: 8) {
                Image(systemName: "lineweight").foregroundStyle(teal)
                Text(String(format: "%.1f pt", Double(store.strokeWidth)))
                    .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
            }
            .frame(maxWidth: .infinity)
            if store.tool == .pen {
                Menu {
                    ForEach(PenProfile.allCases) { profile in
                        Button(profile.rawValue) { store.penProfile = profile }
                    }
                } label: {
                    HStack {
                        Text(store.penProfile.rawValue)
                        Image(systemName: "chevron.down").font(.caption)
                    }
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(teal.opacity(0.08), in: Capsule())
                }
            }
            GeometryReader { geometry in
                let barHeight = geometry.size.height
                let maxSize: CGFloat = store.mode == .art ? 80 : 18
                let proportion = min(1, max(0, (store.strokeWidth - 0.4) / (maxSize - 0.4)))
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 21)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [teal, Color.cyan.opacity(0.95), Color.blue.opacity(0.77)],
                            startPoint: .bottom, endPoint: .top))
                        .frame(width: 21, height: max(8, barHeight * proportion))
                    Circle()
                        .fill(.white)
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(teal, lineWidth: 3))
                        .shadow(color: teal.opacity(0.25), radius: 5)
                        .offset(y: -max(0, barHeight - 34) * proportion)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let ratio = 1 - min(1, max(0, value.location.y / max(1, barHeight)))
                    store.strokeWidth = 0.4 + ratio * (maxSize - 0.4)
                })
            }
            .frame(height: 194)
            .accessibilityLabel("Vertical pen width slider")
            HStack(spacing: 5) {
                ForEach([1.3, 2.5, 5.0, 9.0], id: \.self) { width in
                    Button { store.strokeWidth = CGFloat(width) } label: {
                        Circle()
                            .fill(teal)
                            .frame(width: CGFloat(max(5, min(21, width * 1.65))),
                                   height: CGFloat(max(5, min(21, width * 1.65))))
                            .frame(width: 37, height: 37)
                            .background(Color.primary.opacity(0.055), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Width preset \(width)")
                }
            }
            .frame(maxWidth: .infinity)
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    widthPanelExpanded = false
                }
            } label: {
                Label("Done", systemImage: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(width: 205)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 29, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 29, style: .continuous)
                .stroke(
                    LinearGradient(colors: [
                        Color.cyan.opacity(0.9),
                        Color.blue.opacity(0.7),
                        Color.purple.opacity(0.45),
                        Color.cyan.opacity(0.7)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2.2
                )
                .allowsHitTesting(false)
        }
        .shadow(color: .cyan.opacity(0.22), radius: 19, y: 6)
    }

    private var textNoteCards: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(store.activeTextNotes.filter { note in
                    guard let area = store.focusedArea else { return true }
                    return abs(note.x - area.x) <= (area.width ?? 2400) / 2 &&
                           abs(note.y - area.y) <= (area.height ?? 1600) / 2
                }) { note in
                    let p = CGPoint(x: CGFloat(note.x) * store.zoom - store.offset.x,
                                    y: CGFloat(note.y) * store.zoom - store.offset.y)
                    if p.x > -300 && p.y > -200 && p.x < geometry.size.width + 300 && p.y < geometry.size.height + 200 {
                        Text(note.body)
                            .font(.system(size: max(10, min(21, 17 * store.zoom))))
                            .foregroundStyle(Color(red: 0.12, green: 0.17, blue: 0.20))
                            .frame(width: max(110, min(450, 250 * store.zoom)), alignment: .leading)
                            .padding(10)
                            .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.teal.opacity(0.25)))
                            .onTapGesture { openTextEditor(note) }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { openTextEditor(note) }
                                Button(role: .destructive) { store.trashTextNote(note) } label: {
                                    Label("Move to Trash", systemImage: "trash")
                                }
                            }
                            .gesture(DragGesture(minimumDistance: 8).onEnded { value in
                                store.moveTextNote(note, delta: value.translation)
                            })
                            .position(x: p.x, y: p.y)
                    }
                }
            }
        }
    }
    private func openTextEditor(_ note: TypedNote? = nil) {
        editingNote = note
        textDraft = note?.body ?? ""
        showTextEditor = true
    }

    private var areaPins: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(store.activeAreas.filter { store.focusAreaID == nil || $0.id == store.focusAreaID }) { area in
                    let p = store.screenPoint(for: area)
                    if p.x > -120 && p.y > 0 && p.x < geometry.size.width + 120 && p.y < geometry.size.height {
                        Button { store.goToArea(area); store.zoomToWriting() } label: {
                            Label(area.title, systemImage: "mappin.circle.fill")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .foregroundStyle(teal)
                                .background(.regularMaterial, in: Capsule())
                                .overlay(Capsule().stroke(teal.opacity(0.16)))
                        }
                        .buttonStyle(.plain)
                        .position(x: p.x, y: p.y)
                    }
                }
            }
        }
    }

    private var semanticOverview: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(store.activeAreas.filter { store.focusAreaID == nil || $0.id == store.focusAreaID }) { area in
                    let p = store.screenPoint(for: area)
                    if p.x > -170 && p.y > -100 && p.x < geometry.size.width + 170 && p.y < geometry.size.height + 100 {
                        Button {
                            store.goToArea(area)
                            store.zoomToWriting()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "rectangle.3.group")
                                    Text(CanvasStore.category(for: area.title))
                                        .font(.caption2.weight(.heavy)).tracking(0.7)
                                }.foregroundStyle(teal)
                                Text(area.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text("\(store.clipsNear(area)) saved clips · zoom in to write")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(width: 182, alignment: .leading)
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(teal.opacity(0.35)))
                        }.buttonStyle(.plain)
                        .position(x: p.x, y: p.y)
                    }
                }
            }
        }
    }

    private var lassoActions: some View {
        VStack(spacing: 8) {
            Text("Circle with Pencil → clip automatically saved. Palm and finger touches ignored.")
                .font(.caption).foregroundStyle(.secondary)
            if store.selectionActive, let clip = store.latestClip {
                HStack(spacing: 8) {
                    Label("Captured", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.caption.weight(.semibold))
                    Button("Copy") { store.copyClip(clip) }.buttonStyle(.bordered)
                    Button("Share") { shareURL = store.clipURL(clip); showShare = true }.buttonStyle(.bordered)
                    Button("Open GPT") { openSpecificChat(clip) }.buttonStyle(.borderedProminent)
                    Button("Study prompt") { store.copyStudyPrompt(clip) }.buttonStyle(.bordered)
                    Button("Make area") { store.makeAreaFromSelection() }.buttonStyle(.bordered)
                    Menu {
                        if store.activeAreas.isEmpty { Text("Mark an area first") }
                        ForEach(store.activeAreas) { area in
                            Button(area.title) { store.moveSelection(to: area) }
                        }
                    } label: { Label("Move to area", systemImage: "arrowshape.turn.up.right") }.buttonStyle(.bordered)
                    Button(role: .destructive) { store.deleteSelection() } label: { Image(systemName: "trash") }
                        .buttonStyle(.bordered)
                }.font(.caption)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 18).padding(.bottom, 7)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: store.isSaved ? "checkmark.shield.fill" : "clock")
                .foregroundStyle(store.isSaved ? .green : .orange)
            Text(store.status)
                .lineLimit(1)
            Spacer(minLength: 10)
            Text(String(format: "%.1f%% zoom", Double(store.zoom * 100)))
                .font(.caption.monospacedDigit())
            Text(store.restSafe ? "Palm guard on" : "Two-finger navigation")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private func shareBackup() {
        if let url = store.exportCompleteBackup() { shareURL = url; showShare = true }
    }
    private func openSpecificChat(_ clip: SavedClip) {
        store.copyClip(clip)
        let address = targetChatURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: address), url.scheme == "https", ["chatgpt.com", "www.chatgpt.com"].contains(url.host ?? "") {
            UIApplication.shared.open(url)
        } else { showSettings = true }
    }
}

struct ChatDestinationView: View {
    @ObservedObject var store: CanvasStore
    @Environment(\.dismiss) private var dismiss
    @Binding var conversationURL: String
    @Binding var showAreaPins: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Open a particular ChatGPT chat") {
                    TextField("https://chatgpt.com/c/…", text: $conversationURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Text("Lasso saves the clip as a PNG plus editable PencilKit ink. Open GPT copies that PNG and opens your existing conversation, but you must paste/attach it yourself.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Palm protection") {
                    Label("Pencil-only drawing; move canvas with one finger, zoom with two", systemImage: "hand.raised.fill")
                    Text("The hardware Pencil double-tap and squeeze shortcuts are temporarily disabled pending compatibility testing. This is separate from the right-edge finger double-tap used to hide menus.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("RestSafe allows deliberate one-finger navigation and reserves two-finger gestures for zoom. Navigate also allows two-finger panning. PencilKit rejects finger and palm ink; very large palm contacts may still move the canvas. iPadOS corner gestures remain system-controlled.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Highlighter and interface") {
                    Toggle("Fixed vertical highlighter nib", isOn: $store.fixedHighlighter)
                    Text("Swipe up on the top grip to hide the command bar, down to restore it. Tap or double-tap the right edge for a clean paper-only view. Swipe up from the width icon to open a vertical pen-size control; keep dragging to change thickness, then swipe down or tap Done.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Canvas") {
                    Toggle("Show area labels when zoomed out", isOn: $showAreaPins)
                    Text("Auto-label nearby handwriting uses on-device text recognition; suggested names can be renamed. Isolate an area temporarily hides everything outside its rectangular focus, but does not delete ink. Native Apple Ruler is movable and rotatable using two fingers.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Semantic zoom shows your areas as cards. Organize previews proposed clip course tags, then changes them only after approval. It never rearranges your actual ink. With Lasso, Move to area repositions selected strokes.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Data protection") {
                    Label("Ink autosaves locally", systemImage: "checkmark.shield")
                    Label("Complete JSON backup includes clips and vectors", systemImage: "archivebox")
                    Text("This prototype does not synchronize automatically across devices. Store important backups in Files or iCloud Drive. Local Vision handwriting search is best effort.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Preferences")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Reliable finger-only right-edge gesture
// A distinct UIKit touch target prevents the underlying PencilKit canvas from
// claiming the double tap first. The visible vertical marker is drawn above it.
private struct FingerDoubleTapTarget: UIViewRepresentable {
    var onDoubleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDoubleTap: onDoubleTap)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        let recognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.didDoubleTap(_:))
        )
        recognizer.numberOfTapsRequired = 2
        recognizer.numberOfTouchesRequired = 1
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        recognizer.cancelsTouchesInView = true
        let singleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.didDoubleTap(_:))
        )
        singleTap.numberOfTapsRequired = 1
        singleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        singleTap.require(toFail: recognizer)
        view.addGestureRecognizer(recognizer)
        view.addGestureRecognizer(singleTap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onDoubleTap = onDoubleTap
    }

    final class Coordinator: NSObject {
        var onDoubleTap: () -> Void

        init(onDoubleTap: @escaping () -> Void) {
            self.onDoubleTap = onDoubleTap
        }

        @objc func didDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            onDoubleTap()
        }
    }
}
