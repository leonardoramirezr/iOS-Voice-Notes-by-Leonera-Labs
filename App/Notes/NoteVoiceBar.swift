import SwiftUI

/// The voice control of the note editor: a microphone that turns into an inline recorder (cancel, pause,
/// waveform, send) and into a progress indicator while the command is processed.
struct NoteVoiceBar: View {
    let voice: VoiceCommandModel?
    var onStart: () -> Void
    var onCancel: () -> Void
    var onTogglePause: () -> Void
    var onSend: () -> Void

    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if let voice, voice.phase == .starting || voice.phase == .recording {
                    recorder(voice)
                } else if voice != nil {
                    Spacer()
                    ProgressView()
                        .frame(width: 60, height: 60)
                        .glassEffect(.regular, in: .circle)
                        .glassEffectID("main", in: glassNamespace)
                        .accessibilityLabel(L10n.voiceProcessing)
                } else {
                    Spacer()
                    circleButton(systemImage: "mic.fill", tint: .accentColor, label: L10n.editorVoiceEdit, action: onStart)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .glassEffectID("main", in: glassNamespace)
                }
            }
        }
    }

    @ViewBuilder
    private func recorder(_ voice: VoiceCommandModel) -> some View {
        let isRecording = voice.phase == .recording
        circleButton(systemImage: "xmark", tint: .primary, label: L10n.voiceCancelRecording, action: onCancel)
            .glassEffect(.regular.interactive(), in: .circle)
            .glassEffectID("cancel", in: glassNamespace)
        circleButton(
            systemImage: voice.isPaused ? "play.fill" : "pause.fill",
            tint: .primary,
            label: voice.isPaused ? L10n.voiceResumeRecording : L10n.voicePauseRecording,
            action: onTogglePause
        )
        .disabled(!isRecording)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID("pause", in: glassNamespace)
        WaveformView(levels: voice.levels, isPaused: voice.isPaused)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .glassEffect(.regular, in: .capsule)
            .glassEffectID("waveform", in: glassNamespace)
        circleButton(systemImage: "arrow.up", tint: .white, label: L10n.voiceSend, action: onSend)
            .disabled(!isRecording)
            .glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)
            .glassEffectID("main", in: glassNamespace)
    }

    private func circleButton(
        systemImage: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 60, height: 60)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Bars of the recent input levels, newest on the right.
private struct WaveformView: View {
    static let barWidth: CGFloat = 3
    static let barSpacing: CGFloat = 2

    let levels: [Double]
    let isPaused: Bool

    var body: some View {
        GeometryReader { proxy in
            let count = max(1, Int((proxy.size.width + Self.barSpacing) / (Self.barWidth + Self.barSpacing)))
            let recent = Array(levels.suffix(count))
            let samples = Array(repeating: 0.0, count: count - recent.count) + recent
            HStack(spacing: Self.barSpacing) {
                ForEach(samples.indices, id: \.self) { index in
                    Capsule()
                        .fill(isPaused ? Color.secondary : Color.accentColor)
                        .frame(width: Self.barWidth, height: max(Self.barWidth, proxy.size.height * samples[index]))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .animation(.linear(duration: 0.08), value: levels)
        .accessibilityHidden(true)
    }
}
