import CoreData
import SwiftUI
import VoiceNotesSync

/// The home screen: notes (pinned first) and the floating Liquid Glass menu.
struct NotesListView: View {
    @Environment(AppModel.self) private var app
    @State private var path = NavigationPath()
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var appliedSearch = ""
    @State private var showSettings = false
    @State private var showVoice = false

    var body: some View {
        NavigationStack(path: $path) {
            NotesList(search: appliedSearch)
                .id(appliedSearch)
                .navigationTitle(L10n.notesTitle)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel(L10n.settingsTitle)
                    }
                }
                .navigationDestination(for: NoteRoute.self) { route in
                    destination(for: route)
                }
                .safeAreaBar(edge: .bottom) {
                    FloatingMenuBar(
                        isSearching: $isSearching,
                        searchText: $searchText,
                        onNewNote: { path.append(NoteRoute.new(UUID())) },
                        onVoice: { showVoice = true }
                    )
                }
        }
        .task(id: searchText) {
            // Debounce typing, like the official app.
            try? await Task.sleep(for: .milliseconds(200))
            if !Task.isCancelled {
                appliedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showVoice) {
            VoiceCommandView()
        }
    }

    @ViewBuilder
    private func destination(for route: NoteRoute) -> some View {
        if let engine = app.engine {
            switch route {
            case .note(let objectID):
                if let note = try? engine.context.existingObject(with: objectID) as? Note {
                    NoteEditorView(note: note, engine: engine)
                }
            case .new:
                NoteEditorView(note: nil, engine: engine)
            }
        }
    }
}

/// The list itself; recreated when the search changes so both fetch requests use the new predicate.
private struct NotesList: View {
    @Environment(AppModel.self) private var app
    @FetchRequest private var pinned: FetchedResults<Note>
    @FetchRequest private var others: FetchedResults<Note>
    private let search: String

    init(search: String) {
        self.search = search
        _pinned = FetchRequest(fetchRequest: NoteStore.listFetchRequest(pinned: true, search: search), animation: .default)
        _others = FetchRequest(fetchRequest: NoteStore.listFetchRequest(pinned: false, search: search), animation: .default)
    }

    var body: some View {
        List {
            if !pinned.isEmpty {
                Section(L10n.notesPinned) {
                    ForEach(pinned) { note in
                        row(note)
                    }
                }
            }
            Section {
                ForEach(others) { note in
                    row(note)
                }
            } header: {
                if !pinned.isEmpty, !others.isEmpty {
                    Text(L10n.notesOthers)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if pinned.isEmpty, others.isEmpty {
                emptyState
            }
        }
    }

    private func row(_ note: Note) -> some View {
        NavigationLink(value: NoteRoute.note(note.objectID)) {
            NoteRow(note: note)
        }
        .swipeActions(edge: .leading) {
            Button {
                app.engine?.store.setPinned(note, !note.isPinned)
                app.saveAll()
            } label: {
                Label(note.isPinned ? L10n.notesUnpin : L10n.notesPin, systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                app.engine?.store.setTrashed(note, true)
                app.saveAll()
            } label: {
                Label(L10n.notesTrash, systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if app.isIndexing {
            ProgressView(L10n.notesSyncing)
        } else {
            ContentUnavailableView(
                L10n.notesEmptyTitle,
                systemImage: "note.text",
                description: Text(L10n.notesEmptyMessage)
            )
        }
    }
}
