import SwiftUI
import StriaCore

struct VoiceInputSettingsSection: View {
  @Bindable var settings: SettingsViewModel

  var body: some View {
    Section {
      Picker("Engine", selection: $settings.voiceEngine) {
        ForEach(VoiceOptions.engines, id: \.self) { engine in
          Text(engine == "apple" ? "Apple on-device" : "\(VoiceOptions.engineName(engine)) (sends audio to \(VoiceOptions.engineName(engine)))")
            .tag(engine)
        }
      }
      .onChange(of: settings.voiceEngine) { _, _ in settings.voiceModel = "" }
      if settings.voiceEngine != "apple" {
        HStack {
          TextField("Model (empty = vendor default)", text: $settings.voiceModel)
          Menu("Models") {
            Button("Vendor default") { settings.voiceModel = "" }
            ForEach(VendorSpeechEngine.modelOptions(for: settings.voiceEngine), id: \.self) { model in
              Button(model) { settings.voiceModel = model }
            }
          }
        }
        Text("Choose a suggested model or enter a custom model ID. Uses the vendor's key from Agent API Keys.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Picker("Language", selection: $settings.voiceLanguage) {
        ForEach(settings.voiceLanguageOptions, id: \.self) { language in
          Text(VoiceOptions.languageName(language)).tag(language)
        }
      }
      Toggle("Send automatically after dictation", isOn: $settings.voiceAutoSend)
      Stepper("Recording limit: \(settings.voiceMaxSeconds) seconds", value: $settings.voiceMaxSeconds, in: 10...1800, step: 10)
      Text(VoiceOptions.privacy(settings.voiceEngine)).font(.caption).foregroundStyle(.secondary)
    } header: {
      Text("Voice Input")
    }
  }
}
