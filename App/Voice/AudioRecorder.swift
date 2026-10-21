import AVFoundation
import Foundation

/// Records a voice command as AAC (16 kHz mono, which is what Whisper uses internally).
@MainActor
final class AudioRecorder {
    struct Recording {
        let url: URL
        let duration: TimeInterval
    }

    enum RecorderError: Error {
        case couldNotStart
    }

    static let maximumDuration: TimeInterval = 120

    private var recorder: AVAudioRecorder?
    /// Start of the current recording stretch; nil while paused.
    private var startDate: Date?
    /// Recorded time before the last pause.
    private var recordedBeforePause: TimeInterval = 0
    private(set) var isPaused = false

    var isRecording: Bool {
        recorder?.isRecording ?? false
    }

    /// Recorded time, without the time spent paused.
    var elapsed: TimeInterval {
        guard recorder != nil else {
            return 0
        }
        return recordedBeforePause + (startDate.map { Date().timeIntervalSince($0) } ?? 0)
    }

    func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        default:
            return await AVAudioApplication.requestRecordPermission()
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // Default to the speaker so spoken questions are audible right after recording.
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-command-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record(forDuration: Self.maximumDuration) else {
            throw RecorderError.couldNotStart
        }
        self.recorder = recorder
        startDate = Date()
        recordedBeforePause = 0
        isPaused = false
    }

    func pause() {
        guard let recorder, recorder.isRecording else {
            return
        }
        recorder.pause()
        recordedBeforePause = elapsed
        startDate = nil
        isPaused = true
    }

    /// Continues a paused recording in the same file. The caller stops it at `maximumDuration`.
    func resume() throws {
        guard let recorder, isPaused else {
            return
        }
        guard recorder.record() else {
            throw RecorderError.couldNotStart
        }
        startDate = Date()
        isPaused = false
    }

    /// The input level between 0 and 1, for the recording animation.
    func level() -> Double {
        guard let recorder, recorder.isRecording else {
            return 0
        }
        recorder.updateMeters()
        let decibels = Double(recorder.averagePower(forChannel: 0))
        return min(1, max(0, (decibels + 50) / 50))
    }

    func stop() -> Recording? {
        guard let recorder else {
            return nil
        }
        let duration = elapsed
        recorder.stop()
        self.recorder = nil
        startDate = nil
        recordedBeforePause = 0
        isPaused = false
        return Recording(url: recorder.url, duration: min(duration, Self.maximumDuration))
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        startDate = nil
        recordedBeforePause = 0
        isPaused = false
    }

    /// Gives the audio route back to other apps when the voice flow closes.
    func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
