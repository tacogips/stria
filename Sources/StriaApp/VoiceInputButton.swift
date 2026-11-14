import SwiftUI
import StriaCore

struct VoiceInputButton: View {
  let agent: AgentPaneViewModel

  private var state: DictationState { agent.dictationState }
  private var title: String {
    "\(state.isRecording ? "Stop" : "Start") Dictation (m / Cmd-Shift-M) · \(VoiceOptions.engineName(agent.voiceEngineName))"
  }

  var body: some View {
    HStack(spacing: 4) {
      Button { agent.toggleDictation() } label: {
        switch state {
        case .requestingPermission, .preparing, .transcribing:
          ProgressView().controlSize(.small)
        default:
          Image(systemName: state.isRecording ? "mic.fill" : "mic")
            .font(.title2).foregroundStyle(state.isRecording ? Color.red : Color.secondary)
        }
      }
      .buttonStyle(.plain)
      .disabled(agent.inFlight || (state.isActive && !state.isRecording))
      .accessibilityLabel(state.isRecording ? "Stop dictation" : "Start dictation")
      .help(title)
      if case .recording(let level) = state {
        ProgressView(value: Double(level)).frame(width: 24).tint(.red).accessibilityLabel("Microphone level")
        Text("\((agent.speechInput?.elapsedSeconds ?? 0) / 60):\(String(format: "%02d", (agent.speechInput?.elapsedSeconds ?? 0) % 60))")
          .font(.caption.monospacedDigit())
      }
      if state == .transcribing { Text("Transcribing…").font(.caption).foregroundStyle(.secondary) }
      if state == .preparing { Text("Preparing…").font(.caption).foregroundStyle(.secondary) }
    }
  }
}
