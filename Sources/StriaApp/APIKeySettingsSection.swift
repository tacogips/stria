import SwiftUI
import StriaCore

struct APIKeySettingsSection: View {
  let settings: SettingsViewModel
  @State private var syncEnabled = true
  @State private var revision = 0
  @State private var error: String?

  var body: some View {
    Section {
      Toggle("Sync saved API keys with iCloud Keychain", isOn: Binding(
        get: { syncEnabled },
        set: { enabled in
          do {
            try settings.setCredentialSyncEnabled(enabled)
            syncEnabled = settings.credentialSyncEnabled
            revision += 1
            error = nil
          } catch {
            syncEnabled = settings.credentialSyncEnabled
            self.error = error.localizedDescription
          }
        }
      ))
      ForEach(SettingsViewModel.credentialVendors, id: \.self) { vendor in
        MacCredentialRow(settings: settings, vendor: vendor, revision: revision)
      }
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
    } header: {
      Text("Saved API Keys")
    } footer: {
      Text("Keys save immediately in Keychain. Environment variables still take priority on the Mac. "
           + "Deleting a key removes its local and iCloud copies. Save Settings to apply new variable names.")
    }
    .onAppear { syncEnabled = settings.credentialSyncEnabled }
  }
}

private struct MacCredentialRow: View {
  let settings: SettingsViewModel
  let vendor: String
  let revision: Int
  @State private var value = ""
  @State private var saved = false
  @State private var error: String?
  @State private var confirmingDeletion = false

  var body: some View {
    HStack {
      Text(SettingsViewModel.displayName(for: vendor)).frame(width: 130, alignment: .leading)
      SecureField(saved ? "Replacement key" : "API key", text: $value)
        .textFieldStyle(.roundedBorder)
        .onSubmit(save)
      Button("Save") { save() }.disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      if saved {
        Button("Delete") { confirmingDeletion = true }
          .confirmationDialog("Delete \(SettingsViewModel.displayName(for: vendor)) API key from this Mac and iCloud Keychain?",
                              isPresented: $confirmingDeletion) {
            Button("Delete Key", role: .destructive) {
              do {
                try settings.deleteCredential(for: vendor)
                saved = false
                value = ""
                error = nil
              } catch { self.error = error.localizedDescription }
            }
          }
      }
      Text(saved ? "Saved" : "No key").font(.caption).foregroundStyle(.secondary).frame(width: 50)
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
    }
    .onAppear { saved = settings.hasCredential(for: vendor) }
    .onChange(of: revision) { _, _ in saved = settings.hasCredential(for: vendor) }
    .onDisappear { value = "" }
  }

  private func save() {
    do {
      try settings.saveCredential(value, for: vendor)
      value = ""
      saved = settings.hasCredential(for: vendor)
      error = nil
    } catch { self.error = error.localizedDescription }
  }
}
