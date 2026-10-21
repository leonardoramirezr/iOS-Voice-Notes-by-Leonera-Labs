import SwiftUI
import VoiceNotesCore

/// Full-screen flow of a voice command: recording, progress, questions and the review of the changes.
struct VoiceCommandView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: VoiceCommandModel?
    @State private var showSettings = false
    /// The note the command is given in; nil when the command can change any note.
    var focusedNote: NoteRecord?

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) {
                        close()
                    }
                }
            }
        }
        .task {
            if model == nil {
                let voice = VoiceCommandModel(app: app, focusedNote: focusedNote)
                model = voice
                await voice.startRecording()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    @ViewBuilder
    private func content(_ model: VoiceCommandModel) -> some View {
        switch model.phase {
        case .starting:
            ProgressView()
        case .recording:
            RecordingView(level: model.level, elapsed: model.elapsed, lastQuestion: lastQuestion(model)) {
                model.stopRecording()
            }
        case .transcribing:
            progress(L10n.voiceTranscribing, detail: nil)
        case .planning:
            progress(L10n.voicePlanning, detail: model.lastUserText)
        case .waitingForRateLimit(let seconds):
            progress(L10n.voiceWaitingRateLimit(seconds), detail: model.lastUserText)
        case .saving:
            progress(L10n.voiceSaving, detail: nil)
        case .saved:
            ProgressView()
                .task {
                    close()
                }
        case .clarification(let question):
            ClarificationView(
                question: question,
                transcript: model.lastUserText,
                onReplay: { model.replayQuestion() },
                onAddAudio: { Task { await model.startRecording() } }
            )
        case .review:
            ReviewView(
                changes: model.changes,
                summary: model.summary,
                onCancel: close,
                onAddInstructions: { Task { await model.startRecording() } },
                onSave: { Task { await model.save() } }
            )
            .navigationTitle(L10n.voiceReviewTitle)
        case .failed(let message):
            failure(message, model: model)
        }
    }

    private func lastQuestion(_ model: VoiceCommandModel) -> String? {
        guard let last = model.conversation.last, last.role == .assistant else {
            return nil
        }
        return last.text
    }

    private func progress(_ title: String, detail: String?) -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.headline)
            if let detail {
                Text("“\(detail)”")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private func failure(_ message: String, model: VoiceCommandModel) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if model.needsGroqKey, !app.settings.hasGroqKey {
                Button(L10n.voiceOpenSettings) {
                    showSettings = true
                }
                .buttonStyle(.glassProminent)
            } else {
                Button(L10n.tryAgain) {
                    Task { await model.startRecording() }
                }
                .buttonStyle(.glassProminent)
            }
        }
    }

    private func close() {
        model?.cancel()
        dismiss()
    }
}

/// The microphone while recording: tap anywhere on the button to finish.
private struct RecordingView: View {
    let level: Double
    let elapsed: TimeInterval
    let lastQuestion: String?
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            if let lastQuestion {
                Text(lastQuestion)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Text(L10n.voiceListening)
                .font(.title2.bold())
            Button(action: onStop) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 180, height: 180)
                        .scaleEffect(0.75 + level * 0.4)
                        .animation(.easeOut(duration: 0.12), value: level)
                    Image(systemName: "stop.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 96)
                        .background(Color.accentColor, in: Circle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.voiceTapToFinish)
            Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(L10n.voiceTapToFinish)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// What is missing from the command, read aloud, with a button to add more audio.
private struct ClarificationView: View {
    let question: String
    let transcript: String?
    let onReplay: () -> Void
    let onAddAudio: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            if let transcript {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.voiceYouSaid)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(transcript)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text(question)
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            GlassEffectContainer(spacing: 16) {
                HStack(spacing: 16) {
                    Button(action: onReplay) {
                        Label(L10n.voiceReplay, systemImage: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.glass)
                    Button(action: onAddAudio) {
                        Label(L10n.voiceAddAudio, systemImage: "mic.fill")
                    }
                    .buttonStyle(.glassProminent)
                }
                .controlSize(.large)
            }
        }
        .padding(24)
    }
}
