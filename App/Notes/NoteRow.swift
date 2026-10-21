import SwiftUI
import VoiceNotesSync

struct NoteRow: View {
    @ObservedObject var note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(note.title.isEmpty ? L10n.notesUntitled : note.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel(L10n.notesPinned)
                }
                if let date = note.modificationDate {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
