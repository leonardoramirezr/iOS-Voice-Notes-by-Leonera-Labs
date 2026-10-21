import SwiftUI
import VoiceNotesCore

/// Shows each affected note as one unified diff: added text in green, removed text in red. The note title
/// stays pinned while scrolling and the view opens at the first change.
struct ReviewView: View {
    let changes: [ProposedChange]
    let summary: String?
    let onCancel: () -> Void
    let onAddInstructions: () -> Void
    let onSave: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if let summary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    ForEach(changes) { change in
                        Section {
                            ForEach(change.result.diff) { line in
                                DiffLineRow(line: line)
                                    .id(Self.rowID(change, line))
                            }
                            Spacer(minLength: 24)
                        } header: {
                            NoteTitleHeader(title: change.title, isNew: change.isNew)
                        }
                    }
                }
            }
            .task {
                await Task.yield()
                if let first = firstChangeID {
                    withAnimation {
                        proxy.scrollTo(first, anchor: .center)
                    }
                }
            }
        }
        .safeAreaBar(edge: .bottom) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(L10n.cancel)
                    Button(action: onAddInstructions) {
                        Label(L10n.voiceAddInstructions, systemImage: "mic.fill")
                    }
                    .buttonStyle(.glass)
                    Button(action: onSave) {
                        Label(L10n.save, systemImage: "checkmark")
                            .bold()
                    }
                    .buttonStyle(.glassProminent)
                }
                .controlSize(.large)
            }
            .padding(.bottom, 6)
        }
    }

    private var firstChangeID: String? {
        for change in changes {
            if let index = change.result.firstChangeIndex {
                return Self.rowID(change, change.result.diff[index])
            }
        }
        return nil
    }

    private static func rowID(_ change: ProposedChange, _ line: DiffLine) -> String {
        "\(change.id)-\(line.id)"
    }
}

private struct NoteTitleHeader: View {
    let title: String
    let isNew: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .foregroundStyle(.secondary)
            Text(title.isEmpty ? L10n.notesUntitled : title)
                .font(.headline)
                .lineLimit(1)
            if isNew {
                Text(L10n.voiceNewNoteBadge)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2), in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// One line of the diff. Replaced lines highlight only the words that changed.
struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker)
                .font(.body.monospaced().bold())
                .foregroundStyle(markerColor)
                .frame(width: 14)
            Text(attributedText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .background(background)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var marker: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "−"
        case .context: return " "
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case .added: return .green
        case .removed: return .red
        case .context: return .clear
        }
    }

    private var background: Color {
        switch line.kind {
        case .added: return Color.green.opacity(0.16)
        case .removed: return Color.red.opacity(0.14)
        case .context: return .clear
        }
    }

    private var attributedText: AttributedString {
        let segments = line.segments ?? [WordDiff.Segment(text: line.text, isChanged: false)]
        var result = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            if segment.isChanged {
                part.backgroundColor = line.kind == .added ? Color.green.opacity(0.35) : Color.red.opacity(0.32)
            }
            result += part
        }
        if result.characters.isEmpty {
            result = AttributedString(" ")
        }
        if line.kind == .removed {
            result.strikethroughStyle = .single
            result.foregroundColor = .secondary
        }
        return result
    }

    private var accessibilityText: String {
        switch line.kind {
        case .added: return L10n.voiceAddedLine(line.text)
        case .removed: return L10n.voiceRemovedLine(line.text)
        case .context: return line.text
        }
    }
}
