import SwiftUI
import StriaCore

struct MobileAPIKeySection: View {
  let settings: SettingsViewModel
  @Environment(\.scenePhase) private var scenePhase
  @State private var syncEnabled = true
  @State private var revision = 0
  @State private var error: String?

  var body: some View {
    Section {
      if settings.supportsCredentialSync {
        Toggle("Sync API keys with iCloud Keychain", isOn: Binding(
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
      }
      ForEach(KnownVendors.selectable(on: .iOS), id: \.self) { vendor in
        MobileCredentialRow(settings: settings, vendor: vendor, revision: revision)
      }
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
    } header: {
      Text("API Keys")
    } footer: {
      Text("Keys are saved immediately. With sync enabled, Stria uses iCloud Keychain on devices signed in to the same Apple Account "
           + "with Passwords & Keychain enabled. Turning sync off keeps existing iCloud copies. "
           + "Deleting a key removes its local and iCloud copies. Sync may take time.")
    }
    .onAppear { refresh() }
    .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
  }

  private func refresh() {
    syncEnabled = settings.credentialSyncEnabled
    revision += 1
  }
}

/// Follows Konjac's vendor rows: masked status, replacement field, visibility
/// control and per-vendor removal. Saved secrets are never loaded into the form.
private struct MobileCredentialRow: View {
  let settings: SettingsViewModel
  let vendor: String
  let revision: Int
  @State private var value = ""
  @State private var saved = false
  @State private var visible = false
  @State private var error: String?
  @State private var confirmingDeletion = false
  private var name: String { SettingsViewModel.displayName(for: vendor) }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label(name, systemImage: "key")
        Spacer()
        Text(saved ? "Saved" : "No key set").font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Group {
          if visible { TextField(saved ? "Replacement key" : "API key", text: $value) } else {
            SecureField(saved ? "Replacement key" : "API key", text: $value)
          }
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .accessibilityLabel("\(name) API key")
        .onSubmit(save)
        Button { visible.toggle() } label: { Image(systemName: visible ? "eye.slash" : "eye") }
          .accessibilityLabel(visible ? "Hide API key" : "Show API key")
        if saved {
          Button(role: .destructive) { confirmingDeletion = true } label: { Image(systemName: "trash") }
            .accessibilityLabel("Delete \(name) API key")
        }
      }
      Button("Save Key", action: save).disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
    }
    .buttonStyle(.borderless)
    .padding(.vertical, 4)
    .onAppear { saved = settings.hasCredential(for: vendor) }
    .onChange(of: revision) { _, _ in saved = settings.hasCredential(for: vendor) }
    .onDisappear { value = ""; visible = false }
    .confirmationDialog("Delete \(name) API key from this device and iCloud Keychain?", isPresented: $confirmingDeletion) {
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

  private func save() {
    do {
      try settings.saveCredential(value, for: vendor)
      value = ""
      visible = false
      saved = settings.hasCredential(for: vendor)
      error = nil
    } catch { self.error = error.localizedDescription }
  }
}
