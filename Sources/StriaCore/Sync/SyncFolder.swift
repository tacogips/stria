import Foundation

/// A mobile app resolves its device-local bookmark in the provider at each pass.
public struct SyncFolder: Sendable {
  public struct Location: Sendable {
    public let url: URL
    public let securityScoped: Bool
    public init(url: URL, securityScoped: Bool = false) { self.url = url; self.securityScoped = securityScoped }
  }
  public typealias Provider = @Sendable () throws -> Location?
  private let override: String?
  private let home: URL
  private let platform: StriaPlatform
  private let provider: Provider?

  public init(environment: [String: String] = ProcessInfo.processInfo.environment,
              homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
              platform: StriaPlatform = .current, provider: Provider? = nil) {
    override = environment["STRIA_SYNC_DIR"].flatMap { $0.isEmpty ? nil : $0 }
    home = homeDirectory; self.platform = platform; self.provider = provider
  }

  public func resolve(options: SyncConfig) throws -> Location {
    if let override { return Location(url: URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)) }
    if platform == .macOS {
      if let path = options.folder, !path.isEmpty {
        return Location(url: URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true))
      }
      let cloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
      var directory: ObjCBool = false
      if FileManager.default.fileExists(atPath: cloud.path, isDirectory: &directory), directory.boolValue {
        return Location(url: cloud.appendingPathComponent("Stria", isDirectory: true))
      }
    }
    if let location = try provider?() { return location }
    throw StriaError.serviceUnavailable("iCloud Drive is not available")
  }
}
