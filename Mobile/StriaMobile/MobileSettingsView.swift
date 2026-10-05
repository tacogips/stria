import SwiftUI
import StriaCore
import UniformTypeIdentifiers

struct MobileSettingsView: View {
  @Bindable var settings: SettingsViewModel
  let sync: SyncController
  var showingVendors = false
  @Environment(\.dismiss) private var dismiss
  @AppStorage(Appearance.storageKey) private var appearance = Appearance.default
  @State private var choosingFolder = false
  @State private var vendorNavigation = false
  @State private var folderError: String?

  var body: some View {
    NavigationStack {
      List {
        ocrSection
        summarySection
        Section("API Keys") {
          ForEach(KnownVendors.selectable(on: .iOS), id: \.self) { vendor in
            MobileCredentialRow(settings: settings, vendor: vendor)
          }
        }
        Section("System Prompt") {
          TextEditor(text: $settings.agentSystemPrompt).frame(minHeight: 160).accessibilityLabel("System prompt")
          Button("Reset System Prompt") { settings.resetSystemPrompt() }
          Toggle("Summarize conversations automatically", isOn: $settings.agentAutoSummarize)
        }
        syncSection
        Section("Appearance") {
          Picker("Appearance", selection: $appearance) {
            Text("System").tag(Appearance.system)
            Text("Light").tag(Appearance.light)
            Text("Dark").tag(Appearance.dark)
          }
        }
        if let error = settings.error { Section { Text(error).foregroundStyle(.red) } }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .background(Flat.panel)
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { settings.load(); dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Save") { if settings.save() { dismiss() } } }
      }
      .navigationDestination(isPresented: $vendorNavigation) {
        VendorList(selection: $settings.ocrVendor, options: settings.ocrVendorOptions)
      }
    }
    .onAppear { vendorNavigation = showingVendors }
    .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
      do {
        let url = try result.get()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try MobileSyncFolder.save(url)
        folderError = nil
        sync.configurationChanged()
      } catch { folderError = error.localizedDescription }
    }
  }

  private var ocrSection: some View {
    Section("OCR") {
      NavigationLink {
        VendorList(selection: $settings.ocrVendor, options: settings.ocrVendorOptions)
      } label: {
        LabeledContent("Vendor", value: SettingsViewModel.displayName(for: settings.ocrVendor))
      }
      .onChange(of: settings.ocrVendor) { _, _ in
        settings.ocrAPIKeyEnvironment = SettingsViewModel.suggestedAPIKeyEnvironment(for: settings.ocrVendor) ?? ""
        settings.applySuggestions(ocr: true)
      }
      if SettingsViewModel.needsModel(settings.ocrVendor) {
        ModelField(settings: settings, vendor: settings.ocrVendor, model: $settings.ocrModel)
      }
      Stepper("Format retries: \(settings.ocrFormatRetries)", value: $settings.ocrFormatRetries, in: 0...5)
      Toggle("Run automatically on import", isOn: $settings.ocrAutoRunOnImport)
      TextEditor(text: $settings.ocrPrompt).frame(minHeight: 140).accessibilityLabel("OCR prompt")
      Button("Reset OCR Prompt") { settings.resetOCRPrompt() }
    }
  }

  private var summarySection: some View {
    Section("Page Summaries") {
      NavigationLink {
        VendorList(selection: $settings.summaryVendor, options: settings.summaryVendorOptions)
      } label: {
        LabeledContent("Vendor", value: SettingsViewModel.displayName(for: settings.summaryVendor))
      }
      .onChange(of: settings.summaryVendor) { _, _ in settings.applySummarySuggestions() }
      if SettingsViewModel.needsModel(settings.summaryVendor) {
        ModelField(settings: settings, vendor: settings.summaryVendor, model: $settings.summaryModel)
      }
      Picker("Language", selection: $settings.summaryLanguage) {
        ForEach(settings.summaryLanguageOptions, id: \.self) { Text(PageSummaryLanguage.displayName($0)).tag($0) }
      }
      Toggle("Run automatically after OCR", isOn: $settings.summaryAutoRun)
      TextEditor(text: $settings.summaryPrompt).frame(minHeight: 140).accessibilityLabel("Summary prompt")
      Button("Reset Summary Prompt") { settings.resetSummaryPrompt() }
    }
  }

  private var syncSection: some View {
    Section("iCloud Sync") {
      Toggle("Sync with iCloud Drive", isOn: $settings.syncEnabled)
      Group {
        Toggle("PDFs", isOn: $settings.syncDocuments)
        Toggle("OCR text and tags", isOn: $settings.syncOCR).disabled(!settings.syncDocuments)
        Toggle("Page summaries", isOn: $settings.syncSummaries).disabled(!settings.syncDocuments)
        Toggle("Chat history", isOn: $settings.syncChats)
        Stepper("Interval: \(settings.syncIntervalMinutes) minutes", value: $settings.syncIntervalMinutes, in: 1...120)
      }.disabled(!settings.syncEnabled)
      Text(folderName).font(.caption).foregroundStyle(.secondary)
      Button("Choose iCloud Drive Folder…") { choosingFolder = true }
      Text("Pick or create iCloud Drive/Stria on each device.").font(.caption).foregroundStyle(.secondary)
      if sync.isSyncing { ProgressView("Syncing…") }
      if let date = sync.lastSyncAt { Text("Last synced \(RelativeAge.string(from: date))").font(.caption) }
      if let report = sync.lastReport {
        Text(reportText(report)).font(.caption)
        if report.pending > 0 { Text("\(report.pending) downloads pending").font(.caption) }
      }
      if let error = folderError ?? sync.lastError { Text(error).font(.caption).foregroundStyle(.orange) }
      Button("Sync Now") {
        if settings.save() { Task { await sync.syncNow() } }
      }.disabled(!settings.syncEnabled || sync.isSyncing)
    }
  }

  private var folderName: String {
    if let location = try? MobileSyncFolder.resolve() { return location.url.lastPathComponent }
    return "Choose an iCloud Drive folder to enable sync."
  }

  private func reportText(_ report: SyncReport) -> String {
    "\(report.documents.pushed + report.documents.pulled) PDFs, \(report.ocr.pushed + report.ocr.pulled) pages, "
      + "\(report.summaries.pushed + report.summaries.pulled) summaries, \(report.chats.pushed + report.chats.pulled) chats"
  }
}

/// The mobile list deliberately offers only vendors available on iOS.
struct VendorList: View {
  @Binding var selection: String
  let options: [String]

  var body: some View {
    List(options, id: \.self) { vendor in
      Button { selection = vendor } label: {
        HStack {
          Text(SettingsViewModel.displayName(for: vendor)).foregroundStyle(.primary)
          Spacer()
          if vendor == selection { Image(systemName: "checkmark").accessibilityLabel("Selected") }
        }
      }.accessibilityAddTraits(vendor == selection ? .isSelected : [])
    }
    .listStyle(.plain)
    .navigationTitle("Vendor")
  }
}

struct ModelField: View {
  let settings: SettingsViewModel
  let vendor: String
  @Binding var model: String

  var body: some View {
    HStack {
      TextField("Model", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
      Menu("Models") {
        ForEach(settings.modelOptions(for: vendor, current: model), id: \.self) { option in
          Button(option) { model = option }
        }
      }
    }
  }
}

/// Keys are never reloaded into fields or copied into the config draft.
struct MobileCredentialRow: View {
  let settings: SettingsViewModel
  let vendor: String
  @State private var value = ""
  @State private var saved = false
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(SettingsViewModel.displayName(for: vendor)).font(.headline)
        Spacer()
        Text(saved ? "Saved" : "Not set").font(.caption).foregroundStyle(.secondary)
      }
      SecureField("API key", text: $value)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .accessibilityLabel("\(SettingsViewModel.displayName(for: vendor)) API key")
      HStack {
        Button("Save Key") {
          do {
            try settings.saveCredential(value, for: vendor)
            settings.credentials[vendor] = SettingsViewModel.suggestedAPIKeyEnvironment(for: vendor)
            value = ""
            saved = settings.hasCredential(for: vendor)
            error = nil
          } catch { self.error = error.localizedDescription }
        }.disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button("Delete Key", role: .destructive) {
          do {
            try settings.deleteCredential(for: vendor)
            saved = false
            value = ""
            error = nil
          } catch { self.error = error.localizedDescription }
        }.disabled(!saved)
      }.buttonStyle(.borderless)
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
    }
    .onAppear { saved = settings.hasCredential(for: vendor) }
  }
}
