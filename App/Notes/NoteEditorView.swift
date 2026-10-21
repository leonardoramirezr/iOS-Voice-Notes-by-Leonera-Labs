import Combine
import SwiftUI
import VoiceNotesCore
import VoiceNotesSync

struct NoteEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: NoteEditorModel
    @State private var confirmTrash = false
    @State private var deletedElsewhere = false
    /// The voice command being recorded or processed for this note.
    @State private var voice: VoiceCommandModel?
    @State private var showVoiceReview = false
    @FocusState private var isFocused: Bool

    init(note: Note?, engine: SyncEngine) {
        _model = State(initialValue: NoteEditorModel(note: note, engine: engine))
    }

    var body: some View {
        TextEditor(text: $model.text)
            .font(.body)
            .focused($isFocused)
            .padding(.horizontal, 12)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if model.note != nil {
                        Button {
                            model.togglePinned()
                        } label: {
                            Image(systemName: model.isPinned ? "pin.slash" : "pin")
                        }
                        .accessibilityLabel(model.isPinned ? L10n.notesUnpin : L10n.notesPin)
                        Button {
                            confirmTrash = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(L10n.notesTrash)
                    }
                }
            }
            .safeAreaBar(edge: .bottom) {
                if model.note != nil {
                    NoteVoiceBar(
                        voice: voice,
                        onStart: startVoice,
                        onCancel: cancelVoice,
                        onTogglePause: toggleVoicePause,
                        onSend: { voice?.stopRecording() }
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                }
            }
            .onChange(of: voice?.phase) { _, phase in
                // Processing finished: show the review (or the question or error) full screen.
                switch phase {
                case .some(.review), .some(.clarification), .some(.failed):
                    showVoiceReview = true
                default:
                    break
                }
            }
            .fullScreenCover(isPresented: $showVoiceReview, onDismiss: finishVoice) {
                if let voice {
                    VoiceCommandView(model: voice)
                }
            }
            .onChange(of: model.text) {
                model.textDidChange()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    model.save()
                }
            }
            .onAppear {
                if model.note == nil {
                    isFocused = true
                }
            }
            .onDisappear {
                if !showVoiceReview {
                    // Leaving the note stops a recording in progress.
                    voice?.cancel()
                    voice = nil
                }
                model.save()
            }
            .onReceive(NotificationCenter.default.publisher(for: .notesWillChangeRemotely)) { notification in
                model.remoteChangesWillApply(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .noteDidChangeRemotely)) { notification in
                if model.remoteChangeDidApply(notification) {
                    deletedElsewhere = true
                }
            }
            .confirmationDialog(L10n.editorTrashConfirm, isPresented: $confirmTrash, titleVisibility: .visible) {
                Button(L10n.editorMoveToTrash, role: .destructive) {
                    model.moveToTrash()
                    dismiss()
                }
            }
            .alert(L10n.editorDeletedElsewhere, isPresented: $deletedElsewhere) {
                Button(L10n.ok) {
                    dismiss()
                }
            }
    }

    // MARK: - Voice commands

    /// Starts recording a command that only changes this note.
    private func startVoice() {
        guard voice == nil, let target = model.voiceCommandTarget() else {
            return
        }
        isFocused = false
        let command = VoiceCommandModel(app: app, focusedNote: target)
        withAnimation(.bouncy) {
            voice = command
        }
        Task {
            await command.startRecording()
        }
    }

    private func toggleVoicePause() {
        guard let voice else {
            return
        }
        if voice.isPaused {
            voice.resumeRecording()
        } else {
            voice.pauseRecording()
        }
    }

    private func cancelVoice() {
        voice?.cancel()
        withAnimation(.bouncy) {
            voice = nil
        }
    }

    /// The review was closed (cancelled or saved): back to the note with the saved text.
    private func finishVoice() {
        voice?.cancel()
        voice = nil
        model.reloadSavedContent()
    }
}
