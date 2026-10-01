import Foundation
public struct StriaEnvironment: Sendable {
  public let paths: StriaPaths; public let config: StriaConfig; public let ocrService: any OCRService
  public let agentService: any AgentService; public let clock: @Sendable () -> Date
  public let onRunLogFailure: (@Sendable (String) -> Void)?
  public init(paths: StriaPaths, config: StriaConfig, ocrService: any OCRService, agentService: any AgentService,
              clock: @escaping @Sendable () -> Date = { Date() }, onRunLogFailure: (@Sendable (String) -> Void)? = nil) {
    self.paths = paths; self.config = config; self.ocrService = ocrService; self.agentService = agentService
    self.clock = clock; self.onRunLogFailure = onRunLogFailure
  }
}
