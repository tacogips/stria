import SwiftUI
import StriaCore

/// Settings > Page Summaries: whether pages are summarized after OCR, the
/// vendor and model, the output language, and the prompt template.
struct PageSummarySettingsSection: View {
  @Bindable var settings: SettingsViewModel

  var body: some View {
    Section {
      Toggle("Summarize each page after OCR", isOn: $settings.summaryAutoRun)
      Picker("Vendor", selection: $settings.summaryVendor) {
        ForEach(settings.summaryVendorOptions, id: \.self) { vendor in
          Text(SettingsViewModel.displayName(for: vendor)).tag(vendor)
        }
      }
      .pickerStyle(.menu)
      .onChange(of: settings.summaryVendor) { _, _ in settings.applySummarySuggestions() }
      if SettingsViewModel.needsModel(settings.summaryVendor) {
        ModelField(settings: settings, vendor: settings.summaryVendor, model: $settings.summaryModel) {
          await settings.fetchModels(vendor: settings.summaryVendor, apiKeyEnvironment: settings.summaryCredentialName)
        }
      }
      if SettingsViewModel.requiresAPIKey(settings.summaryVendor) {
        Text(settings.summaryCredentialName.isEmpty
             ? "Set this vendor's key variable under Agent API Keys below."
             : "Uses \(settings.summaryCredentialName) from Agent API Keys.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Picker("Language", selection: $settings.summaryLanguage) {
        ForEach(settings.summaryLanguageOptions, id: \.self) { language in
          Text(PageSummaryLanguage.displayName(language)).tag(language)
        }
      }
      .pickerStyle(.menu)
      TextEditor(text: $settings.summaryPrompt)
        .font(.system(.body, design: .monospaced))
        .frame(minHeight: 120, maxHeight: 240)
        .overlay(Rectangle().stroke(Flat.border, lineWidth: 1))
      HStack {
        Text(settings.summaryPromptIsDefault ? "Using the default prompt." : "Custom prompt.")
          .font(.caption).foregroundStyle(.secondary)
        if !settings.summaryPrompt.contains(PageSummaryDefaults.placeholder) {
          Label("No \(PageSummaryDefaults.placeholder) placeholder", systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.orange)
            .help("The chosen language is inserted where the prompt says \(PageSummaryDefaults.placeholder).")
        }
        Spacer()
        Button("Reset to Default") { settings.resetSummaryPrompt() }
          .disabled(settings.summaryPromptIsDefault)
      }
    } header: {
      Text("Page Summaries")
    } footer: {
      Text("""
        Each page is summarized from its OCR text, with the previous page's text and summary as context. \
        \(PageSummaryDefaults.placeholder) in the prompt becomes the chosen language. Summaries appear in the \
        agent pane's Summary tab and are not searched.
        """)
    }
  }
}
