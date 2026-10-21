import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(L10n.version, value: BuildInfo.versionDescription)
                    LabeledContent(L10n.buildName, value: BuildInfo.buildName)
                    LabeledContent(L10n.localNotes, value: String(model.noteCount))
                }
                if let error = model.startupError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L10n.appName)
        }
    }
}
