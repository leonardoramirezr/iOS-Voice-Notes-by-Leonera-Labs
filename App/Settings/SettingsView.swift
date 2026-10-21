import SwiftUI
import VoiceNotesCore

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var keyStatus: String?
    @State private var isTestingKey = false
    @State private var confirmSignOut = false
    @State private var pendingChanges = 0

    var body: some View {
        @Bindable var settings = app.settings
        NavigationStack {
            Form {
                Section {
                    SecureField(L10n.settingsGroqKeyPlaceholder, text: $apiKey)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(saveKey)
                    HStack {
                        Button(L10n.save, action: saveKey)
                            .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines) == (app.settings.groqAPIKey() ?? ""))
                        Spacer()
                        Button(L10n.settingsTestKey) {
                            Task { await testKey() }
                        }
                        .disabled(isTestingKey || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .buttonStyle(.borderless)
                    if isTestingKey {
                        ProgressView()
                    } else if let keyStatus {
                        Text(keyStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let console = URL(string: "https://console.groq.com/keys") {
                        Link(L10n.settingsGetKey, destination: console)
                            .font(.footnote)
                    }
                } header: {
                    Text(L10n.settingsGroqKey)
                } footer: {
                    Text(L10n.settingsGroqKeyFooter)
                }

                Section(L10n.settingsVoice) {
                    Picker(L10n.settingsChatModel, selection: $settings.chatModel) {
                        ForEach(options(GroqModelSettings.chatModels, current: settings.chatModel), id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    Picker(L10n.settingsTranscriptionModel, selection: $settings.transcriptionModel) {
                        ForEach(options(GroqModelSettings.transcriptionModels, current: settings.transcriptionModel), id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    Picker(L10n.settingsLanguage, selection: $settings.transcriptionLanguage) {
                        ForEach(AppSettings.languages, id: \.self) { code in
                            Text(languageName(code)).tag(code)
                        }
                    }
                    Toggle(L10n.settingsSpeakReplies, isOn: $settings.speakReplies)
                }

                Section(L10n.settingsAccount) {
                    if let account = app.account {
                        Text(account)
                    }
                    Button(L10n.settingsSignOut, role: .destructive) {
                        Task {
                            pendingChanges = await app.pendingChangeCount()
                            confirmSignOut = true
                        }
                    }
                }

                Section(L10n.settingsAbout) {
                    LabeledContent(L10n.version, value: BuildInfo.versionDescription)
                    LabeledContent(L10n.buildName, value: BuildInfo.buildName)
                }
            }
            .navigationTitle(L10n.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.done) {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(L10n.settingsSignOutConfirm, isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button(L10n.settingsSignOut, role: .destructive) {
                    dismiss()
                    Task { await app.signOut() }
                }
            } message: {
                if pendingChanges > 0 {
                    Text(L10n.settingsSignOutPending(pendingChanges))
                }
            }
        }
        .onAppear {
            apiKey = app.settings.groqAPIKey() ?? ""
        }
    }

    private func saveKey() {
        do {
            try app.settings.setGroqAPIKey(apiKey)
            keyStatus = L10n.settingsKeySaved
        } catch {
            keyStatus = error.localizedDescription
        }
    }

    private func testKey() async {
        isTestingKey = true
        defer { isTestingKey = false }
        do {
            let models = try await GroqClient(apiKey: apiKey).listModels()
            keyStatus = L10n.settingsKeyWorks(models.count)
            if apiKey.trimmingCharacters(in: .whitespacesAndNewlines) != (app.settings.groqAPIKey() ?? "") {
                saveKey()
                keyStatus = L10n.settingsKeyWorks(models.count)
            }
        } catch {
            keyStatus = VoiceErrorMessages.message(for: error)
        }
    }

    /// The known options plus the current value, so a custom model chosen earlier stays selectable.
    private func options(_ known: [String], current: String) -> [String] {
        known.contains(current) ? known : known + [current]
    }

    private func languageName(_ code: String) -> String {
        if code == AppSettings.automaticLanguage {
            return L10n.settingsLanguageAutomatic
        }
        return Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
    }
}
