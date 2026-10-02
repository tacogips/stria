import Foundation

/// Holds the current configuration so a change saved from the app's Settings
/// window applies to the next OCR or ask call without reopening the library.
public final class ConfigBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value: StriaConfig
  public init(_ value: StriaConfig) { self.value = value }
  public var config: StriaConfig {
    get { lock.lock(); defer { lock.unlock() }; return value }
    set { lock.lock(); value = newValue; lock.unlock() }
  }
}

public struct StriaEnvironment: Sendable {
  public let paths: StriaPaths; public let ocrService: any OCRService
  public let agentService: any AgentService; public let clock: @Sendable () -> Date
  public let onRunLogFailure: (@Sendable (String) -> Void)?
  private let configBox: ConfigBox
  public var config: StriaConfig { configBox.config }

  public init(paths: StriaPaths, config: StriaConfig, ocrService: any OCRService, agentService: any AgentService,
              clock: @escaping @Sendable () -> Date = { Date() }, onRunLogFailure: (@Sendable (String) -> Void)? = nil) {
    self.paths = paths; configBox = ConfigBox(config); self.ocrService = ocrService; self.agentService = agentService
    self.clock = clock; self.onRunLogFailure = onRunLogFailure
  }

  /// Replaces the in-memory configuration (the file is written by `StriaLibrary.saveConfig`).
  public func updateConfig(_ config: StriaConfig) { configBox.config = config }
}
