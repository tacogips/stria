import AppKit
import SwiftUI
import StriaCore

struct SyncSettingsSection: View {
  @Bindable var settings: SettingsViewModel
  let sync: SyncController

  var body: some View {
    Section("iCloud Sync") {
      Toggle("Sync with iCloud Drive", isOn: $settings.syncEnabled)
      Group {
        Toggle("PDFs", isOn: $settings.syncDocuments)
        Toggle("OCR text and tags", isOn: $settings.syncOCR).disabled(!settings.syncDocuments)
        Toggle("Page summaries", isOn: $settings.syncSummaries).disabled(!settings.syncDocuments)
        Toggle("Chat history", isOn: $settings.syncChats)
        Stepper("Sync every \(settings.syncIntervalMinutes) minutes", value: $settings.syncIntervalMinutes, in: 1...120)
      }
      .disabled(!settings.syncEnabled)
      Text(settings.syncFolder.isEmpty ? sync.folderDescription : settings.syncFolder)
        .font(.caption).textSelection(.enabled)
      HStack {
        Button("Choose Folder...") { chooseFolder() }
        Button("Use Default") { settings.syncFolder = "" }.disabled(settings.syncFolder.isEmpty)
      }
      TimelineView(.periodic(from: .now, by: 30)) { _ in
        if let date = sync.lastSyncAt, let report = sync.lastReport {
          Text("Last synced \(RelativeAge.string(from: date)): \(total(report.documents)) PDFs, \(total(report.ocr)) pages, \(total(report.summaries)) summaries, \(total(report.chats)) chats")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      if let report = sync.lastReport, report.pending > 0 {
        Text("\(report.pending) pending downloads").font(.caption).foregroundStyle(.secondary)
      }
      if let error = sync.lastError {
        Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
      }
      HStack {
        Button("Sync Now") {
          if settings.save() { Task { await sync.syncNow() } }
        }
        .disabled(!settings.syncEnabled || sync.isSyncing)
        if sync.isSyncing { ProgressView().controlSize(.small) }
      }
    }
  }

  private func total(_ counts: SyncCounts) -> Int { counts.pushed + counts.pulled }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false; panel.canChooseDirectories = true
    panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
    panel.prompt = "Choose"
    if panel.runModal() == .OK, let url = panel.url { settings.syncFolder = url.path }
  }
}
