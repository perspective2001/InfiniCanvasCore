import SwiftUI

struct OrganizationPreviewView: View {
    @ObservedObject var store: CanvasStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("What will change") {
                    Text("Suggestions affect the course tags on saved clippings, not the writing or the locations of your notes. They are based on labels and best-effort handwriting recognition.")
                        .font(.footnote)
                    if store.organizationProposal.isEmpty {
                        ContentUnavailableView("Nothing to regroup", systemImage: "checkmark.seal",
                            description: Text("Add named areas and lasso clippings, then try again."))
                    }
                    ForEach(store.activeClips.filter { store.organizationProposal[$0.id] != nil }) { clip in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(clip.title).font(.headline)
                                Text(clip.course ?? "Unsorted").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            Text(store.organizationProposal[clip.id] ?? "Unsorted").foregroundStyle(.teal).bold()
                        }
                    }
                }
                Section("Safety") {
                    Label("No strokes are moved or deleted", systemImage: "shield.checkered")
                    Label("Changes require approval", systemImage: "hand.tap")
                    Label("Undo last organization in More menu", systemImage: "arrow.uturn.backward")
                }
            }
            .navigationTitle("Preview organization")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.organizationPreview = false; dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { store.applyOrganization(); dismiss() }
                        .disabled(store.organizationProposal.isEmpty)
                }
            }
        }
    }
}

struct LectureLibraryView: View {
    @ObservedObject var store: CanvasStore
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: LectureSession?
    @State private var proposedName = ""
    @State private var showRename = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.recording {
                        HStack {
                            Label("Recording \(Int(store.recordingSeconds))s", systemImage: "record.circle.fill")
                                .foregroundStyle(.red)
                            Spacer()
                            Button("Mark") { store.addLectureMark() }.buttonStyle(.bordered)
                            Button("Stop") { store.endLectureRecording() }.buttonStyle(.borderedProminent)
                        }
                    } else {
                        Button { store.beginLectureRecording() } label: {
                            Label("Record lecture", systemImage: "record.circle")
                        }
                    }
                    Text("Record only with permission. Tap Mark while writing to link the current canvas position to the recording time. Lasso clips are bookmarked automatically while recording.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if store.lectureSessions.isEmpty {
                    ContentUnavailableView("No lectures yet", systemImage: "waveform",
                        description: Text("Record a lecture, add bookmarks, and jump back to the exact point from your handwritten notes."))
                }
                ForEach(store.lectureSessions) { lecture in
                    Section {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(lecture.title).font(.headline)
                                Text("\(Int(lecture.duration))s · \(lecture.marks.count) ink markers")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Play") { store.playLecture(lecture) }.buttonStyle(.bordered)
                            Button { renaming = lecture; proposedName = lecture.title; showRename = true } label: {
                                Image(systemName: "pencil")
                            }.buttonStyle(.bordered)
                        }
                        ForEach(lecture.marks) { mark in
                            Button {
                                store.goToLectureMark(lecture, mark: mark)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "bookmark.fill")
                                    Text("At \(formatSeconds(mark.seconds))")
                                    Spacer()
                                    Text("Jump to handwriting + audio")
                                        .foregroundStyle(.secondary).font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lecture time travel")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if store.playingSessionID != nil {
                        Button("Stop audio") { store.stopLecturePlayback() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Rename lecture", isPresented: $showRename) {
                TextField("Lecture name", text: $proposedName)
                Button("Save") {
                    if let lecture = renaming, !proposedName.trimmingCharacters(in: .whitespaces).isEmpty {
                        store.renameLecture(lecture, name: proposedName)
                    }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }
    private func formatSeconds(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
