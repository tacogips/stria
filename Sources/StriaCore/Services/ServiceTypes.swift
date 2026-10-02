public struct ServiceSettings: Equatable, Sendable {
  public var vendor: String; public var model: String?; public var apiKeyEnvironment: String?
  /// Wall-clock bound for one model call; `GatewayPromptRunner` cancels the
  /// gateway session and fails the call when it is exceeded.
  public var timeoutSeconds: Int
  public init(vendor: String, model: String?, apiKeyEnvironment: String?, timeoutSeconds: Int = 300) {
    self.vendor = vendor; self.model = model; self.apiKeyEnvironment = apiKeyEnvironment; self.timeoutSeconds = timeoutSeconds
  }
  /// An unconfigured vendor becomes "" and is rejected by preflight.
  public init(ocr: StriaConfig.OCRConfig) {
    self.init(vendor: ocr.vendor ?? "", model: ocr.model, apiKeyEnvironment: ocr.apiKeyEnvironment, timeoutSeconds: ocr.timeoutSeconds)
  }
  public init(agent: StriaConfig.AgentConfig) {
    self.init(agent: agent, vendor: agent.vendor ?? "", model: agent.model)
  }
  /// Settings for a vendor and model chosen per question; the credential
  /// comes from the agent's per-vendor table.
  public init(agent: StriaConfig.AgentConfig, vendor: String, model: String?) {
    self.init(vendor: vendor, model: model, apiKeyEnvironment: agent.credential(for: vendor), timeoutSeconds: agent.timeoutSeconds)
  }
}
public enum ServiceError: Error, Equatable, Sendable { case unavailable(String), failed(String) }
