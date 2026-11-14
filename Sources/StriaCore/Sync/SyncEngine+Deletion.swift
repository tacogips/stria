import Foundation

extension SyncEngine {
  /// Best effort immediate publication. The durable local intent is cleared
  /// only after all remote cleanup succeeds; failures retry on the next pass.
  func publishDeletion(id: String, date: Date) async throws {
    let location = try library.environment.syncFolder.resolve(options: library.environment.config.sync)
    let access = location.securityScoped && location.url.startAccessingSecurityScopedResource()
    guard !location.securityScoped || access else { throw StriaError.serviceUnavailable("iCloud Drive is not available") }
    defer { if access { location.url.stopAccessingSecurityScopedResource() } }
    let format = location.url.appendingPathComponent("format.json")
    let placeholder = location.url.appendingPathComponent(".format.json.icloud")
    guard try !files.exists(placeholder) else { throw StriaError.io("Sync format is pending download") }
    if try files.exists(format) {
      guard try files.read(SyncFormat.self, at: format).version == 1 else { throw StriaError.io("Unsupported sync format version") }
    } else {
      try files.write(SyncFormat(version: 1), at: format)
    }
    try writeTombstone(id: id, date: date, folder: location.url)
    try await library.store.setMeta("sync.deleted." + id, nil)
  }
}
