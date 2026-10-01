public struct ServiceSettings: Equatable, Sendable {
  public var vendor: String; public var model: String?; public var apiKeyEnvironment: String?
  public init(vendor: String, model: String?, apiKeyEnvironment: String?) { self.vendor = vendor; self.model = model; self.apiKeyEnvironment = apiKeyEnvironment }
  public init(ocr: StriaConfig.OCRConfig) { self.init(vendor: ocr.vendor, model: ocr.model, apiKeyEnvironment: ocr.apiKeyEnvironment) }
  public init(agent: StriaConfig.AgentConfig) { self.init(vendor: agent.vendor, model: agent.model, apiKeyEnvironment: agent.apiKeyEnvironment) }
}
public enum ServiceError: Error, Equatable, Sendable { case unavailable(String), failed(String) }
