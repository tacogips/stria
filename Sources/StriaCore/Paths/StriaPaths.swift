import Foundation

public struct StriaPaths: Equatable, Sendable {
  public let root: URL

  public init(root: URL) { self.root = root.standardizedFileURL }

  public var database: URL { root.appendingPathComponent("stria.sqlite") }
  public var originals: URL { root.appendingPathComponent("originals", isDirectory: true) }
  public var cache: URL { root.appendingPathComponent("cache", isDirectory: true) }
  public var config: URL { root.appendingPathComponent("config.json") }
  public var logs: URL { root.appendingPathComponent("logs", isDirectory: true) }
  public var allLocations: [URL] { [root, database, originals, cache, config, logs] }

  public func original(docId: String) -> URL { originals.appendingPathComponent("\(docId).pdf") }
  public func cacheDirectory(docId: String) -> URL { cache.appendingPathComponent(docId, isDirectory: true) }
  public func cachedPage(docId: String, page: Int) -> URL {
    cacheDirectory(docId: docId).appendingPathComponent(String(format: "page-%04d.png", page))
  }
  public func runLog(for date: Date) -> URL {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    let name = String(format: "agent-runs-%04d-%02d-%02d.jsonl", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    return logs.appendingPathComponent(name)
  }

  public func ensureDirectories() throws {
    let manager = FileManager.default
    do {
      for directory in [root, originals, cache, logs] {
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      }
      #if os(iOS)
      var cacheURL = cache
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try cacheURL.setResourceValues(values)
      #endif
    } catch {
      throw StriaError.io("Could not create data directories: \(error.localizedDescription)")
    }
  }

  /// The data root in the user's home or the mobile app container.
  public static func defaultRoot(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
                                 platform: StriaPlatform = .current) -> URL {
    switch platform {
    case .macOS: homeDirectory.appendingPathComponent(".local/stria", isDirectory: true)
    case .iOS: homeDirectory.appendingPathComponent("Library/Application Support/Stria", isDirectory: true)
    }
  }

  public static func resolve(
    homeFlag: String?, environment: [String: String], homeDirectory: URL, currentDirectory: URL,
    platform: StriaPlatform = .current
  ) -> StriaPaths {
    let selected = [homeFlag, environment["STRIA_HOME"]].compactMap { $0 }.first { !$0.isEmpty }
    let candidate: URL
    if let selected {
      candidate = selected.hasPrefix("/")
        ? URL(fileURLWithPath: selected)
        : currentDirectory.appendingPathComponent(selected)
    } else {
      candidate = defaultRoot(homeDirectory: homeDirectory, platform: platform)
    }
    return StriaPaths(root: candidate.standardizedFileURL)
  }
}
