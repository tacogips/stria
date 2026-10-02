import SwiftUI
import StriaCore

/// The Settings window (Cmd-,): OCR and agent vendor, model and credential
/// variable, and whether OCR runs automatically after import.
struct SettingsView: View {
  @Bindable var settings: SettingsViewModel

  var body: some View {
    Form {
      Section("OCR") {
        Picker("Vendor", selection: $settings.ocrVendor) {
          ForEach(SettingsViewModel.ocrVendorOptions, id: \.self) { vendor in
            Text(SettingsViewModel.displayName(for: vendor)).tag(vendor)
          }
        }
        .onChange(of: settings.ocrVendor) { _, _ in settings.applySuggestions(ocr: true) }
        if SettingsViewModel.needsModel(settings.ocrVendor) {
          TextField("Model", text: $settings.ocrModel, prompt: Text(SettingsViewModel.suggestedModel(for: settings.ocrVendor) ?? "model id"))
        }
        if SettingsViewModel.requiresAPIKey(settings.ocrVendor) {
          TextField("API key environment variable", text: $settings.ocrAPIKeyEnvironment,
                    prompt: Text(SettingsViewModel.suggestedAPIKeyEnvironment(for: settings.ocrVendor) ?? "NAME"))
          Text("The variable's name only. Its value is read from the environment the app was launched from and never stored.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Toggle("Run OCR automatically after import", isOn: $settings.ocrAutoRunOnImport)
        Text(settings.ocrAutoRunOnImport
             ? "Pages are OCRed as soon as a PDF is imported."
             : "Pages wait until you choose Run OCR for a document in the library.")
          .font(.caption).foregroundStyle(.secondary)
        Stepper("Concurrent pages: \(settings.ocrConcurrency)", value: $settings.ocrConcurrency, in: 1...8)
      }
      Section("Agent") {
        Picker("Vendor", selection: $settings.agentVendor) {
          ForEach(SettingsViewModel.agentVendorOptions, id: \.self) { vendor in
            Text(SettingsViewModel.displayName(for: vendor)).tag(vendor)
          }
        }
        .onChange(of: settings.agentVendor) { _, _ in settings.applySuggestions(ocr: false) }
        if SettingsViewModel.needsModel(settings.agentVendor) {
          TextField("Model", text: $settings.agentModel, prompt: Text(SettingsViewModel.suggestedModel(for: settings.agentVendor) ?? "model id"))
        }
        if SettingsViewModel.requiresAPIKey(settings.agentVendor) {
          TextField("API key environment variable", text: $settings.agentAPIKeyEnvironment,
                    prompt: Text(SettingsViewModel.suggestedAPIKeyEnvironment(for: settings.agentVendor) ?? "NAME"))
        }
      }
      Section {
        TextEditor(text: $settings.agentSystemPrompt)
          .font(.system(.body, design: .monospaced))
          .frame(minHeight: 160)
        HStack {
          Text(settings.systemPromptIsDefault ? "Using the default prompt." : "Custom prompt.")
            .font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button("Reset to Default") { settings.resetSystemPrompt() }
            .disabled(settings.systemPromptIsDefault)
        }
      } header: {
        Text("System Prompt")
      } footer: {
        Text("Sent with every question. Stria adds the retrieved pages and the question after it.")
      }
      Section {
        HStack {
          if let error = settings.error {
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
          } else if let savedAt = settings.savedAt {
            Text("Saved \(savedAt, style: .relative) ago").font(.callout).foregroundStyle(.secondary)
          }
          Spacer()
          Button("Revert") { settings.load() }
          Button("Save") { settings.save() }
            .keyboardShortcut(.defaultAction)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 560, height: 720)
    .padding(.bottom, 8)
    .onAppear { settings.load() }
  }
}
