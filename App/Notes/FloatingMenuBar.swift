import SwiftUI

/// The floating Liquid Glass menu of the notes list: Search, Add manually, Add via audio.
/// Search morphs the capsule into a glass search field.
struct FloatingMenuBar: View {
    @Binding var isSearching: Bool
    @Binding var searchText: String
    var onNewNote: () -> Void
    var onVoice: () -> Void

    @Namespace private var glassNamespace
    @FocusState private var searchFocused: Bool

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            if isSearching {
                searchField
            } else {
                menu
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .onChange(of: isSearching) { _, searching in
            searchFocused = searching
        }
    }

    private var menu: some View {
        HStack(spacing: 4) {
            menuButton(L10n.menuSearch, systemImage: "magnifyingglass") {
                withAnimation(.bouncy) {
                    isSearching = true
                }
            }
            menuButton(L10n.menuNewNote, systemImage: "square.and.pencil", action: onNewNote)
            menuButton(L10n.menuVoice, systemImage: "mic.fill", tint: .accentColor, action: onVoice)
        }
        .padding(.horizontal, 8)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("menu", in: glassNamespace)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.menuSearchPlaceholder, text: $searchText)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.menuClearSearch)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("menu", in: glassNamespace)

            Button {
                searchText = ""
                withAnimation(.bouncy) {
                    isSearching = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 52, height: 52)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .glassEffectID("close", in: glassNamespace)
            .accessibilityLabel(L10n.menuCloseSearch)
        }
    }

    private func menuButton(
        _ title: String,
        systemImage: String,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 72, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
