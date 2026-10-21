import SwiftUI

/// Chooses the screen for the current session state.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.route {
        case .loggedOut:
            LoginView()
        case .sessionExpired(let email):
            LoginView(expiredEmail: email)
        case .ready:
            if let engine = app.engine {
                NotesListView()
                    .environment(\.managedObjectContext, engine.context)
            }
        case .signingOut:
            ProgressView(L10n.signingOut)
        case .failed(let message):
            ContentUnavailableView(L10n.startupFailed, systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }
}
