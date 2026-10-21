import Combine
import SwiftUI
import VoiceNotesCore
import VoiceNotesSync

struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: NoteEditorModel
    @State private var confirmTrash = false
    @State private var deletedElsewhere = false
    @State private var showVoice = false
    @State private var voiceTarget: NoteRecord?
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
                    HStack {
                        Spacer()
                        voiceButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                }
            }
            .fullScreenCover(isPresented: $showVoice, onDismiss: { model.reloadSavedContent() }) {
                VoiceCommandView(focusedNote: voiceTarget)
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

    /// Floating button that dictates a change to this note only.
    private var voiceButton: some View {
        Button {
            guard let target = model.voiceCommandTarget() else {
                return
            }
            isFocused = false
            voiceTarget = target
            showVoice = true
        } label: {
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 60, height: 60)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(L10n.editorVoiceEdit)
    }
}
