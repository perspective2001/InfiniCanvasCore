import SwiftUI
import UIKit

struct ClipLibraryView: View {
    @ObservedObject var store: CanvasStore
    let onOpenChat: (SavedClip) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var searchText = ""
    @State private var shareClip: SavedClip?
    @State private var renameClip: SavedClip?
    @State private var renameArea: CanvasArea?
    @State private var renameText = ""
    @State private var showRenameClip = false
    @State private var showRenameArea = false
    @State private var previewClip: SavedClip?
    @State private var editingAreaLabels = false

    private var filteredClips: [SavedClip] {
        store.activeClips
            .filter { clip in
                searchText.isEmpty || [clip.title, clip.recognizedText ?? "", clip.course ?? ""]
                    .joined(separator: " ").localizedCaseInsensitiveContains(searchText)
            }
            .sorted {
                if $0.isPinned == true && $1.isPinned != true { return true }
                if $1.isPinned == true && $0.isPinned != true { return false }
                return $0.createdAt > $1.createdAt
            }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Library section", selection: $tab) {
                    Text("Clips").tag(0)
                    Text("Study \(store.dueClips.count)").tag(1)
                    Text("Areas").tag(2)
                    Text("Text").tag(3)
                    Text("Trash").tag(4)
                }.pickerStyle(.segmented).padding(14)
                switch tab {
                case 0: clipsList
                case 1: reviewList
                case 2: areasList
                case 3: textNotesList
                default: trashList
                }
            }
            .navigationTitle("Your canvas library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $shareClip) { clip in SystemShareSheet(items: [store.clipURL(clip)]) }
            .sheet(item: $previewClip) { clip in clipPreview(clip) }
            .alert("Rename clipping", isPresented: $showRenameClip) {
                TextField("Clipping name", text: $renameText)
                Button("Save") {
                    if let clip = renameClip {
                        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !title.isEmpty { store.renameClip(clip, to: title) }
                    }
                    renameClip = nil
                }
                Button("Cancel", role: .cancel) { renameClip = nil }
            }
            .alert("Rename area", isPresented: $showRenameArea) {
                TextField("Area name", text: $renameText)
                Button("Save") {
                    if let area = renameArea {
                        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !title.isEmpty { store.renameArea(area, to: title) }
                    }
                    renameArea = nil
                }
                Button("Cancel", role: .cancel) { renameArea = nil }
            }
        }
    }

    private var clipsList: some View {
        List {
            if filteredClips.isEmpty {
                ContentUnavailableView("No matching clippings", systemImage: "lasso",
                    description: Text("Lasso any handwriting to save a clean PNG and editable ink here. Search also checks recognized handwriting."))
            }
            ForEach(filteredClips) { clip in clipRow(clip) }
            Section {
                Text("Clips save automatically when you finish circling. OCR runs on-device as a best-effort background index; the original ink and PNG are preserved whether recognition succeeds or not.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find writing, course or clip")
    }

    private func clipRow(_ clip: SavedClip) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Button { previewClip = clip } label: { clipThumbnail(clip).frame(width: 120, height: 90) }
                .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    if clip.isPinned == true { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                    Text(clip.title).font(.headline)
                }
                HStack(spacing: 6) {
                    Text(clip.course ?? "Unsorted")
                    Text("·")
                    Text(clip.createdAt, style: .date)
                    Text("·")
                    Text("\(clip.strokeCount) strokes")
                }
                .font(.caption).foregroundStyle(.secondary)
                if let recognized = clip.recognizedText, !recognized.isEmpty {
                    Text(recognized).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 8) {
                    Button("Copy") { store.copyClip(clip) }.buttonStyle(.bordered)
                    Button("GPT") { onOpenChat(clip); dismiss() }.buttonStyle(.borderedProminent)
                    Button("Study") { store.markReview(clip) }.buttonStyle(.bordered)
                    Menu { clipMoreMenu(clip) } label: { Image(systemName: "ellipsis.circle") }
                        .buttonStyle(.bordered)
                }.font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .swipeActions {
            Button("Trash", role: .destructive) { store.deleteClip(clip) }
            Button("Pin") { store.togglePin(clip) }.tint(.orange)
        }
    }

    @ViewBuilder
    private func clipMoreMenu(_ clip: SavedClip) -> some View {
        Button("Preview", systemImage: "eye") { previewClip = clip }
        Button("Share image", systemImage: "square.and.arrow.up") { shareClip = clip }
        Button("Paste editable ink", systemImage: "pencil.tip.crop.circle.badge.plus") {
            store.pasteClipAsInk(clip); dismiss()
        }
        if clip.sourceX != nil {
            Button("Find original ink", systemImage: "location") { store.goToClip(clip); dismiss() }
        }
        Button(clip.isPinned == true ? "Unpin" : "Pin", systemImage: "pin") { store.togglePin(clip) }
        Button("Rename", systemImage: "pencil") {
            renameClip = clip; renameText = clip.title; showRenameClip = true
        }
        Button("Add to study queue", systemImage: "rectangle.stack") { store.markReview(clip) }
        Button("Copy AI study prompt", systemImage: "doc.on.clipboard") { store.copyStudyPrompt(clip) }
        if clip.audioSessionID != nil {
            Button("Play linked lecture moment", systemImage: "waveform") { store.playFromClip(clip); dismiss() }
        }
        Button("Move to Trash", systemImage: "trash", role: .destructive) { store.deleteClip(clip) }
    }

    private var reviewList: some View {
        List {
            Section("Ready to review") {
                if store.dueClips.isEmpty {
                    ContentUnavailableView("All caught up", systemImage: "checkmark.seal",
                        description: Text("Tap Study on any saved clipping to add it to the queue. Review items remain on your canvas."))
                }
                ForEach(store.dueClips) { clip in
                    HStack {
                        clipThumbnail(clip).frame(width: 100, height: 70)
                        VStack(alignment: .leading) {
                            Text(clip.title).font(.headline)
                            Text(clip.recognizedText ?? clip.course ?? "Handwritten clip")
                                .font(.caption).lineLimit(2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            ForEach(ReviewRating.allCases) { rating in
                                Button(rating.rawValue) { store.completeReview(clip, rating: rating) }
                            }
                        } label: { Label("Review", systemImage: "checkmark.circle") }
                            .buttonStyle(.borderedProminent)
                    }.padding(.vertical, 4)
                }
            }
            Section("How this works") {
                Text("Rate your recall: Again, Hard, Good, or Easy schedules the next review at increasing intervals. Copy AI study prompt to ChatGPT; question generation and AI grading are not performed inside this app.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var areasList: some View {
        List {
            if store.groupedAreas.isEmpty {
                ContentUnavailableView("No area bookmarks", systemImage: "mappin.and.ellipse",
                    description: Text("Add a label at your current position. All areas remain on one continuous canvas."))
            }
            ForEach(store.groupedAreas.indices, id: \.self) { groupIndex in
                let section = store.groupedAreas[groupIndex]
                Section(section.0) {
                    ForEach(section.1) { area in
                        HStack {
                            Button { store.goToArea(area); dismiss() } label: {
                                Label(area.title, systemImage: "mappin.circle")
                            }
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.48).onEnded { _ in
                                    withAnimation { editingAreaLabels = true }
                                }
                            )
                            Spacer()
                            if editingAreaLabels {
                                Button(role: .destructive) {
                                    store.deleteArea(area)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                        .font(.system(size: 19))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(area.title) categorization")
                            }
                            Menu {
                                Button("Go to area", systemImage: "location") { store.goToArea(area); dismiss() }
                                Button("Rename", systemImage: "pencil") {
                                    renameArea = area; renameText = area.title; showRenameArea = true
                                }
                                Button("Trash label", systemImage: "trash", role: .destructive) { store.deleteArea(area) }
                            } label: { Image(systemName: "ellipsis.circle") }
                        }
                    }
                }
            }
            if editingAreaLabels {
                Button("Done editing labels") { editingAreaLabels = false }
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Organize alphabetizes and groups subject labels here. It never moves your handwriting without an explicit Lasso → Move to area action.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var textNotesList: some View {
        List {
            if store.activeTextNotes.isEmpty {
                ContentUnavailableView("No typed notes", systemImage: "textformat",
                    description: Text("Tap Type above the canvas to add text without leaving the continuous page."))
            }
            ForEach(store.activeTextNotes) { note in
                HStack {
                    Button { store.goToTextNote(note); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.body).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                            Text("Tap to jump to this writing").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button(role: .destructive) { store.trashTextNote(note) } label: {
                        Image(systemName: "trash")
                    }.buttonStyle(.bordered)
                }.padding(.vertical, 5)
            }
        }
    }

    private var trashList: some View {
        List {
            Section("Clippings") {
                if store.discardedClips.isEmpty { Text("No discarded clips").foregroundStyle(.secondary) }
                ForEach(store.discardedClips) { clip in
                    HStack {
                        clipThumbnail(clip).frame(width: 90, height: 58)
                        Text(clip.title)
                        Spacer()
                        Button("Restore") { store.restoreClip(clip) }.buttonStyle(.bordered)
                    }
                }
            }
            Section("Typed notes") {
                ForEach(store.discardedTextNotes) { note in
                    HStack {
                        Text(note.body).lineLimit(1)
                        Spacer()
                        Button("Restore") { store.restoreTextNote(note) }.buttonStyle(.bordered)
                    }
                }
            }
            Section("Area labels") {
                if store.discardedAreas.isEmpty { Text("No discarded areas").foregroundStyle(.secondary) }
                ForEach(store.discardedAreas) { area in
                    HStack {
                        Text(area.title)
                        Spacer()
                        Button("Restore") { store.restoreArea(area) }.buttonStyle(.bordered)
                    }
                }
            }
            Section {
                Text("Trash removes library entries from view, not their original ink. This version does not permanently purge clip files from storage.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func clipThumbnail(_ clip: SavedClip) -> some View {
        Group {
            if let img = store.clipImage(clip) {
                Image(uiImage: img).resizable().scaledToFit().padding(6)
            } else { Image(systemName: "scribble.variable").foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black.opacity(0.08)))
    }

    private func clipPreview(_ clip: SavedClip) -> some View {
        NavigationStack {
            VStack(spacing: 15) {
                clipThumbnail(clip).padding(20).frame(maxHeight: 360)
                if let recognized = clip.recognizedText, !recognized.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Recognized handwriting (check accuracy)").font(.caption.weight(.semibold))
                        Text(recognized).textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                }
                HStack(spacing: 12) {
                    Button("Copy") { store.copyClip(clip) }.buttonStyle(.bordered)
                    Button("Share") { shareClip = clip }.buttonStyle(.bordered)
                    Button("Ask GPT") { previewClip = nil; onOpenChat(clip); dismiss() }.buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            .navigationTitle(clip.title)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { previewClip = nil } } }
        }
    }
}
