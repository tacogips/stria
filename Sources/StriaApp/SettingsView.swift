import SwiftUI
import StriaCore

/// The Settings window (Cmd-,): OCR and agent vendor, model and credential
/// variable, and whether OCR runs automatically after import.
struct SettingsView: View {
  @Bindable var settings: SettingsViewModel
  @AppStorage(Appearance.storageKey) private var appearance = Appearance.default

  /// A scrolling form with the Save / Revert bar pinned below it, so the
  /// buttons stay reachable at any window height; the window is resizable.
  var body: some View {
    VStack(spacing: 0) {
      form
      Divider()
      footer
    }
    .frame(minWidth: 520, idealWidth: 580, minHeight: 420, idealHeight: 640)
    .onAppear { settings.load() }
  }

  private var footer: some View {
    HStack {
      if let error = settings.error {
        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout).lineLimit(2)
      } else if let savedAt = settings.savedAt {
        Text("Saved \(RelativeAge.string(from: savedAt))").font(.callout).foregroundStyle(.secondary)
      }
      Spacer()
      Button("Revert") { settings.load() }
      Button("Save") { settings.save() }
        .keyboardShortcut(.defaultAction)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Flat.panel)
  }

  private var form: some View {
    Form {
      Section("Appearance") {
        Picker("Theme", selection: $appearance) {
          ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        Text("Light is the default. Shift+D in the reader toggles light and dark.").font(.caption).foregroundStyle(.secondary)
      }
      Section("OCR") {
        Picker("Vendor", selection: $settings.ocrVendor) {
          ForEach(SettingsViewModel.ocrVendorOptions, id: \.self) { vendor in
            Text(SettingsViewModel.displayName(for: vendor)).tag(vendor)
          }
        }
        .pickerStyle(.menu)
        .onChange(of: settings.ocrVendor) { _, _ in settings.applySuggestions(ocr: true) }
        if SettingsViewModel.needsModel(settings.ocrVendor) {
          ModelField(settings: settings, vendor: settings.ocrVendor, model: $settings.ocrModel, ocr: true)
        }
        if SettingsViewModel.requiresAPIKey(settings.ocrVendor) {
          TextField("API key environment variable", text: $settings.ocrAPIKeyEnvironment,
                    prompt: Text(SettingsViewModel.suggestedAPIKeyEnvironment(for: settings.ocrVendor) ?? "NAME"))
          Text("The variable's name only. Its value is read from the environment the app was launched from and never stored.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Toggle("Run OCR automatically after import", isOn: $settings.ocrAutoRunOnImport)
        Stepper("Concurrent pages: \(settings.ocrConcurrency)", value: $settings.ocrConcurrency, in: 1...8)
      }
      Section("Agent") {
        Picker("Vendor", selection: $settings.agentVendor) {
          ForEach(SettingsViewModel.agentVendorOptions, id: \.self) { vendor in
            Text(SettingsViewModel.displayName(for: vendor)).tag(vendor)
          }
        }
        .pickerStyle(.menu)
        .onChange(of: settings.agentVendor) { _, _ in settings.applySuggestions(ocr: false) }
        if SettingsViewModel.needsModel(settings.agentVendor) {
          ModelField(settings: settings, vendor: settings.agentVendor, model: $settings.agentModel, ocr: false)
        }
        if SettingsViewModel.requiresAPIKey(settings.agentVendor) {
          TextField("API key environment variable", text: $settings.agentAPIKeyEnvironment,
                    prompt: Text(SettingsViewModel.suggestedAPIKeyEnvironment(for: settings.agentVendor) ?? "NAME"))
        }
      }
      Section {
        TextEditor(text: $settings.agentSystemPrompt)
          .font(.system(.body, design: .monospaced))
          .frame(minHeight: 120, maxHeight: 240)
          .overlay(Rectangle().stroke(Flat.border, lineWidth: 1))
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
    }
    .formStyle(.grouped)
  }
}

/// Model picker limited to the chosen vendor's models, with "Custom…" for
/// any other id and, for API vendors, a live refresh from the vendor. The
/// option list is computed once per vendor (or fetch), not on every render,
/// so choosing an entry applies without a visible delay.
private struct ModelField: View {
  @Bindable var settings: SettingsViewModel
  let vendor: String
  @Binding var model: String
  let ocr: Bool
  @State private var custom = false
  @State private var options: [String] = []

  private var fetchedCount: Int { settings.fetchedModels[vendor]?.count ?? 0 }

  private var selection: Binding<String> {
    Binding(
      get: { custom ? SettingsViewModel.customModel : (options.contains(model) ? model : SettingsViewModel.customModel) },
      set: { value in
        if value == SettingsViewModel.customModel {
          custom = true
          model = ""
        } else {
          custom = false
          model = value
        }
      }
    )
  }

  var body: some View {
    Picker("Model", selection: selection) {
      ForEach(options, id: \.self) { Text($0).tag($0) }
      Divider()
      Text("Custom…").tag(SettingsViewModel.customModel)
    }
    .pickerStyle(.menu)
    .onAppear { refreshOptions() }
    .onChange(of: vendor) { _, _ in
      custom = false
      refreshOptions()
    }
    .onChange(of: fetchedCount) { _, _ in refreshOptions() }
    if custom || (!model.isEmpty && !options.contains(model)) {
      TextField("Model id", text: $model, prompt: Text("model id as the vendor names it"))
        .textFieldStyle(FlatTextFieldStyle())
    }
    if settings.canFetchModels(for: vendor) {
      HStack {
        Button(settings.isFetchingModels ? "Fetching…" : "Fetch models from vendor") {
          Task { await settings.fetchModels(ocr: ocr) }
        }
        .disabled(settings.isFetchingModels)
        if let error = settings.modelFetchError {
          Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
        } else if fetchedCount > 0 {
          Text("\(fetchedCount) models").font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }

  private func refreshOptions() {
    options = settings.modelOptions(for: vendor, current: custom ? "" : model)
  }
}
