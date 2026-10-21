import Foundation

/// Every user-facing string. Keys and the English/Spanish translations live in Resources/Localizable.xcstrings.
enum L10n {
    static var appName: String { String(localized: "app.name", defaultValue: "Voice Notes") }
    static var ok: String { String(localized: "common.ok", defaultValue: "OK") }
    static var cancel: String { String(localized: "common.cancel", defaultValue: "Cancel") }
    static var done: String { String(localized: "common.done", defaultValue: "Done") }
    static var save: String { String(localized: "common.save", defaultValue: "Save") }
    static var tryAgain: String { String(localized: "common.tryAgain", defaultValue: "Try again") }
    static var networkError: String { String(localized: "common.networkError", defaultValue: "The network could not be reached. Check your connection and try again.") }
    static var signingOut: String { String(localized: "app.signingOut", defaultValue: "Logging out…") }
    static var startupFailed: String { String(localized: "app.startupFailed", defaultValue: "The app could not open its database") }
    static var loginSubtitle: String { String(localized: "login.subtitle", defaultValue: "Your Simplenote notes, edited with your voice.") }
    static var loginEmail: String { String(localized: "login.email", defaultValue: "Email") }
    static var loginSendCode: String { String(localized: "login.sendCode", defaultValue: "Send login code") }
    static func loginCodeSent(_ email: String) -> String {
        String(localized: "login.codeSent", defaultValue: "We sent a code to \(email). Enter it below.")
    }
    static var loginCode: String { String(localized: "login.code", defaultValue: "6-character code") }
    static var loginLogIn: String { String(localized: "login.logIn", defaultValue: "Log in") }
    static var loginResendCode: String { String(localized: "login.resendCode", defaultValue: "Send a new code") }
    static var loginDifferentEmail: String { String(localized: "login.differentEmail", defaultValue: "Use a different email") }
    static var createAccount: String { String(localized: "login.createAccount", defaultValue: "No account? Create one at simplenote.com") }
    static var sessionExpired: String { String(localized: "login.sessionExpired", defaultValue: "Your session expired. Log in again to keep syncing.") }
    static var loginInvalidEmail: String { String(localized: "login.invalidEmail", defaultValue: "Enter a valid email address.") }
    static var loginInvalidCode: String { String(localized: "login.invalidCode", defaultValue: "The code is not correct. Check it and try again.") }
    static var loginCodeExpired: String { String(localized: "login.codeExpired", defaultValue: "The code expired. Request a new one.") }
    static var loginTooManyAttempts: String { String(localized: "login.tooManyAttempts", defaultValue: "Too many attempts. Wait a few minutes and try again.") }
    static var loginFailed: String { String(localized: "login.failed", defaultValue: "Login failed. Try again.") }
    static var notesTitle: String { String(localized: "notes.title", defaultValue: "Notes") }
    static var notesPinned: String { String(localized: "notes.pinned", defaultValue: "Pinned") }
    static var notesOthers: String { String(localized: "notes.others", defaultValue: "Notes") }
    static var notesUntitled: String { String(localized: "notes.untitled", defaultValue: "Untitled") }
    static var notesEmptyTitle: String { String(localized: "notes.emptyTitle", defaultValue: "No notes yet") }
    static var notesEmptyMessage: String { String(localized: "notes.emptyMessage", defaultValue: "Tap the microphone to add a note with your voice, or the pencil to write one.") }
    static var notesSyncing: String { String(localized: "notes.syncing", defaultValue: "Syncing your notes…") }
    static var notesPin: String { String(localized: "notes.pin", defaultValue: "Pin") }
    static var notesUnpin: String { String(localized: "notes.unpin", defaultValue: "Unpin") }
    static var notesTrash: String { String(localized: "notes.trash", defaultValue: "Move to Trash") }
    static var menuSearch: String { String(localized: "menu.search", defaultValue: "Search") }
    static var menuNewNote: String { String(localized: "menu.newNote", defaultValue: "Add manually") }
    static var menuVoice: String { String(localized: "menu.voice", defaultValue: "Add via audio") }
    static var menuSearchPlaceholder: String { String(localized: "menu.searchPlaceholder", defaultValue: "Search notes") }
    static var menuClearSearch: String { String(localized: "menu.clearSearch", defaultValue: "Clear search") }
    static var menuCloseSearch: String { String(localized: "menu.closeSearch", defaultValue: "Close search") }
    static var editorNewNote: String { String(localized: "editor.newNote", defaultValue: "New note") }
    static var editorTrashConfirm: String { String(localized: "editor.trashConfirm", defaultValue: "Move this note to the trash?") }
    static var editorMoveToTrash: String { String(localized: "editor.moveToTrash", defaultValue: "Move to Trash") }
    static var editorDeletedElsewhere: String { String(localized: "editor.deletedElsewhere", defaultValue: "This note was deleted on another device.") }
    static var settingsTitle: String { String(localized: "settings.title", defaultValue: "Settings") }
    static var settingsGroqKey: String { String(localized: "settings.groqKey", defaultValue: "Groq API key") }
    static var settingsGroqKeyPlaceholder: String { String(localized: "settings.groqKeyPlaceholder", defaultValue: "gsk_…") }
    static var settingsGroqKeyFooter: String { String(localized: "settings.groqKeyFooter", defaultValue: "Used to transcribe and understand voice commands. Stored in the Keychain of this iPhone.") }
    static var settingsGetKey: String { String(localized: "settings.getKey", defaultValue: "Get a key at console.groq.com") }
    static var settingsTestKey: String { String(localized: "settings.testKey", defaultValue: "Test key") }
    static var settingsKeySaved: String { String(localized: "settings.keySaved", defaultValue: "Key saved.") }
    static func settingsKeyWorks(_ count: Int) -> String {
        String(localized: "settings.keyWorks", defaultValue: "The key works (\(count) models available).")
    }
    static var settingsVoice: String { String(localized: "settings.voice", defaultValue: "Voice commands") }
    static var settingsChatModel: String { String(localized: "settings.chatModel", defaultValue: "Language model") }
    static var settingsTranscriptionModel: String { String(localized: "settings.transcriptionModel", defaultValue: "Transcription model") }
    static var settingsLanguage: String { String(localized: "settings.language", defaultValue: "Spoken language") }
    static var settingsLanguageAutomatic: String { String(localized: "settings.languageAutomatic", defaultValue: "Detect automatically") }
    static var settingsSpeakReplies: String { String(localized: "settings.speakReplies", defaultValue: "Read questions aloud") }
    static var settingsAccount: String { String(localized: "settings.account", defaultValue: "Simplenote account") }
    static var settingsSignOut: String { String(localized: "settings.signOut", defaultValue: "Log out") }
    static var settingsSignOutConfirm: String { String(localized: "settings.signOutConfirm", defaultValue: "Log out and remove the notes stored on this iPhone?") }
    static func settingsSignOutPending(_ count: Int) -> String {
        String(localized: "settings.signOutPending", defaultValue: "\(count) changes have not reached Simplenote yet and will be lost.")
    }
    static var settingsAbout: String { String(localized: "settings.about", defaultValue: "About") }
    static var version: String { String(localized: "settings.version", defaultValue: "Version") }
    static var buildName: String { String(localized: "settings.buildName", defaultValue: "Build") }
    static var voiceListening: String { String(localized: "voice.listening", defaultValue: "Listening…") }
    static var voiceTapToFinish: String { String(localized: "voice.tapToFinish", defaultValue: "Tap the button when you finish") }
    static var voiceTranscribing: String { String(localized: "voice.transcribing", defaultValue: "Transcribing…") }
    static var voicePlanning: String { String(localized: "voice.planning", defaultValue: "Preparing the changes…") }
    static func voiceWaitingRateLimit(_ seconds: Int) -> String {
        String(localized: "voice.waitingRateLimit", defaultValue: "Groq is busy. Retrying in \(seconds) s…")
    }
    static var voiceSaving: String { String(localized: "voice.saving", defaultValue: "Saving…") }
    static var voiceYouSaid: String { String(localized: "voice.youSaid", defaultValue: "You said") }
    static var voiceReplay: String { String(localized: "voice.replay", defaultValue: "Read again") }
    static var voiceAddAudio: String { String(localized: "voice.addAudio", defaultValue: "Add audio") }
    static var voiceReviewTitle: String { String(localized: "voice.reviewTitle", defaultValue: "Review changes") }
    static var voiceAddInstructions: String { String(localized: "voice.addInstructions", defaultValue: "Add instructions") }
    static var voiceNewNoteBadge: String { String(localized: "voice.newNoteBadge", defaultValue: "New note") }
    static func voiceAddedLine(_ text: String) -> String {
        String(localized: "voice.addedLine", defaultValue: "Added: \(text)")
    }
    static func voiceRemovedLine(_ text: String) -> String {
        String(localized: "voice.removedLine", defaultValue: "Removed: \(text)")
    }
    static var voiceClarificationFallback: String { String(localized: "voice.clarificationFallback", defaultValue: "I couldn't tell which note to change or what to change. Say it again with the note name and the change.") }
    static var voiceNothingHeard: String { String(localized: "voice.nothingHeard", defaultValue: "I didn't hear anything. Try again closer to the microphone.") }
    static var voiceMicrophoneDenied: String { String(localized: "voice.microphoneDenied", defaultValue: "Microphone access is off. Turn it on in Settings › Voice Notes.") }
    static var voiceRecordingFailed: String { String(localized: "voice.recordingFailed", defaultValue: "Recording could not start.") }
    static var voiceGroqKeyMissing: String { String(localized: "voice.groqKeyMissing", defaultValue: "Add your Groq API key in Settings to use voice commands.") }
    static var voiceOpenSettings: String { String(localized: "voice.openSettings", defaultValue: "Open Settings") }
    static var voiceGroqUnauthorized: String { String(localized: "voice.groqUnauthorized", defaultValue: "Groq rejected the API key. Check it in Settings.") }
    static var voiceGroqRateLimited: String { String(localized: "voice.groqRateLimited", defaultValue: "Groq's usage limit was reached. Wait a minute and try again.") }
    static var voiceCommandTooLong: String { String(localized: "voice.commandTooLong", defaultValue: "The command or the note is too long for Groq.") }
    static func voiceGroqFailed(_ details: String) -> String {
        String(localized: "voice.groqFailed", defaultValue: "Groq could not process the command (\(details)).")
    }
    static func voiceNoteMissing(_ title: String) -> String {
        String(localized: "voice.noteMissing", defaultValue: "The note “\(title)” no longer exists.")
    }
}
