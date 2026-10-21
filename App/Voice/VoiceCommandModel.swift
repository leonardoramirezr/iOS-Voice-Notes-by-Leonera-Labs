import Foundation
import Observation
import VoiceNotesCore

/// Drives a voice command: record, transcribe with Whisper, plan with the LLM, ask for what is missing,
/// review and save. The conversation is kept so extra audio completes or corrects the command. A command given
/// inside a note only changes that note.
@MainActor
@Observable
final class VoiceCommandModel {
    enum Phase: Equatable {
        case starting
        case recording
        case transcribing
        case planning
        case waitingForRateLimit(seconds: Int)
        case clarification(String)
        case review
        case saving
        case saved
        case failed(String)
    }

    /// Longest rate-limit pause the app waits for before giving up.
    static let maximumRateLimitWait: TimeInterval = 20
    /// Input levels kept for the waveform.
    static let levelHistoryCount = 40

    private(set) var phase: Phase = .starting
    private(set) var conversation: [ConversationTurn] = []
    private(set) var changes: [ProposedChange] = []
    private(set) var summary: String?
    private(set) var level: Double = 0
    /// Recent input levels, oldest first, for the waveform.
    private(set) var levels: [Double] = []
    private(set) var isPaused = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var needsGroqKey = false

    private let app: AppModel
    /// The note the command was given in; nil when the command can change any note.
    private let focusedNote: NoteRecord?
    private let recorder = AudioRecorder()
    private let speech = SpeechPlayer()
    private var language: String?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var meterTask: Task<Void, Never>?

    init(app: AppModel, focusedNote: NoteRecord? = nil) {
        self.app = app
        self.focusedNote = focusedNote
    }

    var lastUserText: String? {
        conversation.last { $0.role == .user }?.text
    }

    // MARK: - Recording

    func startRecording() async {
        work?.cancel()
        speech.stop()
        guard app.settings.groqAPIKey() != nil else {
            needsGroqKey = true
            phase = .failed(L10n.voiceGroqKeyMissing)
            return
        }
        guard await recorder.requestPermission() else {
            phase = .failed(L10n.voiceMicrophoneDenied)
            return
        }
        do {
            try recorder.start()
        } catch {
            phase = .failed(L10n.voiceRecordingFailed)
            return
        }
        levels = []
        isPaused = false
        phase = .recording
        startMetering()
    }

    func pauseRecording() {
        guard phase == .recording, !isPaused else {
            return
        }
        recorder.pause()
        isPaused = true
        level = 0
    }

    func resumeRecording() {
        guard phase == .recording, isPaused else {
            return
        }
        do {
            try recorder.resume()
            isPaused = false
        } catch {
            meterTask?.cancel()
            recorder.cancel()
            phase = .failed(L10n.voiceRecordingFailed)
        }
    }

    func stopRecording() {
        meterTask?.cancel()
        level = 0
        isPaused = false
        guard phase == .recording, let recording = recorder.stop() else {
            return
        }
        phase = .transcribing
        work = Task { [weak self] in
            await self?.process(recording)
        }
    }

    func cancel() {
        work?.cancel()
        meterTask?.cancel()
        recorder.cancel()
        speech.stop()
        recorder.deactivateSession()
    }

    func replayQuestion() {
        if case .clarification(let message) = phase {
            speech.speak(message, language: language)
        }
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                if self.recorder.elapsed >= AudioRecorder.maximumDuration
                    || (!self.recorder.isRecording && !self.recorder.isPaused) {
                    // The recording reached its maximum length.
                    self.stopRecording()
                    return
                }
                if !self.recorder.isPaused {
                    let level = self.recorder.level()
                    self.level = level
                    self.levels.append(level)
                    if self.levels.count > Self.levelHistoryCount {
                        self.levels.removeFirst(self.levels.count - Self.levelHistoryCount)
                    }
                }
                self.elapsed = self.recorder.elapsed
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    // MARK: - Processing

    private func process(_ recording: AudioRecorder.Recording) async {
        defer { try? FileManager.default.removeItem(at: recording.url) }
        guard let apiKey = app.settings.groqAPIKey() else {
            needsGroqKey = true
            phase = .failed(L10n.voiceGroqKeyMissing)
            return
        }
        let client = GroqClient(apiKey: apiKey)
        phase = .transcribing
        do {
            let audio = try Data(contentsOf: recording.url)
            let titles = focusedNote.map { [$0.title] } ?? app.noteRecords().prefix(20).map(\.title)
            let transcription = try await client.transcribe(
                audio: audio,
                fileName: "command.m4a",
                mimeType: "audio/m4a",
                model: app.settings.transcriptionModel,
                language: app.settings.whisperLanguage,
                prompt: Prompts.transcriptionPrompt(titles: Array(titles))
            )
            let text = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard recording.duration >= 0.6, !transcription.isLikelySilence, !text.isEmpty else {
                phase = .failed(L10n.voiceNothingHeard)
                return
            }
            conversation.append(ConversationTurn(role: .user, text: text))
            try await plan(client: client)
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(VoiceErrorMessages.message(for: error))
        }
    }

    private func plan(client: GroqClient) async throws {
        phase = .planning
        let pipeline = CommandPipeline(model: GroqPlanningModel(client: client, model: app.settings.chatModel))
        let outcome: PipelineOutcome
        do {
            outcome = try await run(pipeline)
        } catch GroqError.rateLimited(let retryAfter) where (retryAfter ?? 5) <= Self.maximumRateLimitWait {
            let seconds = Int((retryAfter ?? 5).rounded(.up))
            phase = .waitingForRateLimit(seconds: seconds)
            try await Task.sleep(for: .seconds(seconds))
            phase = .planning
            outcome = try await run(pipeline)
        }
        switch outcome {
        case .clarification(let message, let language):
            let question = message ?? (focusedNote == nil ? L10n.voiceClarificationFallback : L10n.voiceNoteClarificationFallback)
            conversation.append(ConversationTurn(role: .assistant, text: question))
            self.language = language
            changes = []
            phase = .clarification(question)
            if app.settings.speakReplies {
                speech.speak(question, language: language)
            }
        case .review(let proposed, let summary, let language):
            changes = proposed
            self.summary = summary
            self.language = language
            phase = .review
        }
    }

    /// Plans against the current notes, or only against the current text of the focused note.
    private func run(_ pipeline: CommandPipeline) async throws -> PipelineOutcome {
        guard let focusedNote else {
            return try await pipeline.plan(conversation: conversation, notes: app.noteRecords())
        }
        guard let note = app.noteRecord(withKey: focusedNote.key) else {
            throw NoteSaveError.noteMissing(focusedNote.title)
        }
        return try await pipeline.plan(conversation: conversation, in: note)
    }

    // MARK: - Saving

    /// Saves the reviewed changes. If a note changed so much meanwhile that the edits no longer apply, the
    /// command is planned again against the current notes.
    func save() async {
        phase = .saving
        do {
            try app.save(changes)
            speech.stop()
            phase = .saved
        } catch {
            guard let apiKey = app.settings.groqAPIKey() else {
                phase = .failed(VoiceErrorMessages.message(for: error))
                return
            }
            do {
                try await plan(client: GroqClient(apiKey: apiKey))
            } catch {
                phase = .failed(VoiceErrorMessages.message(for: error))
            }
        }
    }
}
