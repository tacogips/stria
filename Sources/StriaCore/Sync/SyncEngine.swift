import Foundation

public struct SyncEngine: Sendable {
  let library: StriaLibrary
  let files: SyncFiles
  private let download: @Sendable (URL) throws -> Void

  public init(library: StriaLibrary, download: @escaping @Sendable (URL) throws -> Void = {
    try FileManager.default.startDownloadingUbiquitousItem(at: $0)
  }) {
    self.library = library; self.download = download
    files = SyncFiles(coordinator: library.environment.syncFileCoordinator)
  }

  /// Explicit passes (including the CLI) run even if automatic sync is off.
  public func sync(folder: URL? = nil, options: SyncConfig? = nil) async throws -> SyncReport {
    let options = options ?? library.environment.config.sync
    let location = try folder.map { SyncFolder.Location(url: $0) } ?? library.environment.syncFolder.resolve(options: options)
    return try await sync(location: location, options: options)
  }

  public func sync(location: SyncFolder.Location, options: SyncConfig) async throws -> SyncReport {
    try options.validate()
    let folder = location.url.resolvingSymlinksInPath()
    let access = location.securityScoped && location.url.startAccessingSecurityScopedResource()
    guard !location.securityScoped || access else { throw StriaError.serviceUnavailable("iCloud Drive is not available (folder access denied)") }
    defer { if access { location.url.stopAccessingSecurityScopedResource() } }
    var report = SyncReport(folder: location.url.path)
    do {
      if try files.exists(folder) {
        let directory = try files.coordinate(folder) { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
        guard directory else { throw StriaError.serviceUnavailable("iCloud Drive is not available (sync folder is not a directory)") }
      }
    } catch {
      throw StriaError.serviceUnavailable("iCloud Drive is not available (sync folder cannot be opened)")
    }
    // Inspect the version before downloads, directory creation or store changes.
    let formatURL = folder.appendingPathComponent("format.json")
    if try files.exists(formatURL) {
      let format = try files.read(SyncFormat.self, at: formatURL)
      guard format.version <= 1 else { throw StriaError.io("Sync format version \(format.version) is newer than supported version 1") }
      guard format.version == 1 else { throw StriaError.io("Unsupported sync format version \(format.version)") }
    }
    let pending = try placeholders(in: folder, report: &report)
    if pending.contains(formatURL.path) { return report }
    do { try files.createDirectory(folder) } catch {
      throw StriaError.serviceUnavailable("iCloud Drive is not available (sync folder cannot be opened)")
    }
    if try !files.exists(formatURL) { try files.write(SyncFormat(version: 1), at: formatURL) }
    if options.documents {
      await syncDocuments(folder: folder, options: options, pending: pending, report: &report)
    }
    if options.chats { await syncChats(folder: folder, options: options, pending: pending, report: &report) }
    return report
  }

  private func placeholders(in folder: URL, report: inout SyncReport) throws -> Set<String> {
    var pending = Set<String>()
    for url in try files.children(folder) {
      do {
        let name = url.lastPathComponent
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
          let original = String(name.dropFirst().dropLast(".icloud".count))
          pending.insert(url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(original).path)
          report.pending += 1
          try download(url)
        } else if try files.coordinate(url, { url in
          let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
          return values.isDirectory == true && values.isSymbolicLink != true
        }) {
          pending.formUnion(try placeholders(in: url, report: &report))
        }
      } catch { itemError(error, item: url.lastPathComponent, report: &report) }
    }
    return pending
  }

  static func safeID(_ value: String) -> Bool {
    !value.isEmpty && value != "." && value != ".." && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
  }

  func itemError(_ error: Error, item: String, report: inout SyncReport) {
    report.errors.append("\(item): \((error as? StriaError)?.message ?? error.localizedDescription)")
  }

  /// Used by removal as well as retries at the start of a pass.
  func writeTombstone(id: String, date: Date, folder: URL) throws {
    guard Self.safeID(id) else { throw StriaError.io("Invalid document id") }
    let directory = folder.appendingPathComponent("documents/\(id)")
    let tombstone = directory.appendingPathComponent("deleted.json")
    let previous = try files.exists(tombstone) ? files.read(SyncTombstone.self, at: tombstone).deletedAt : nil
    try files.write(SyncTombstone(deletedAt: max(previous ?? date, date)), at: tombstone)
    for name in ["original.pdf", "ocr", "summaries"] { try files.remove(directory.appendingPathComponent(name)) }
  }
}
