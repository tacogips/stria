import Foundation

public enum KnownVendors {
  public static let gateway = ["claude-code", "codex", "cursor", "cursor-api", "openai", "anthropic", "gemini", "openrouter"]
  public static let pdfTextLayer = "pdf-text-layer"
  public static let apiKeyVendors: Set<String> = ["openai", "anthropic", "gemini", "openrouter", "cursor-api"]
}

private enum RenderConfigCodingKeys: String, CodingKey { case dpi, imageFormat, quality, maxPixelDimension }
private enum OCRConfigCodingKeys: String, CodingKey { case vendor, model, apiKeyEnvironment, concurrency, prompt }
private enum AgentConfigCodingKeys: String, CodingKey { case vendor, model, apiKeyEnvironment, neighborPages, maxImages, maxContextCharacters, systemPrompt }
private enum StriaConfigCodingKeys: String, CodingKey { case version, render, ocr, agent }

public struct StriaConfig: Codable, Equatable, Sendable {
  public struct RenderConfig: Codable, Equatable, Sendable {
    public var dpi: Int
    public var imageFormat: ImageFormat
    public var quality: Double
    public var maxPixelDimension: Int

    public init(dpi: Int, imageFormat: ImageFormat, quality: Double, maxPixelDimension: Int) {
      self.dpi = dpi; self.imageFormat = imageFormat; self.quality = quality; self.maxPixelDimension = maxPixelDimension
    }
    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: RenderConfigCodingKeys.self)
      self.init(dpi: try c.decodeIfPresent(Int.self, forKey: .dpi) ?? 150,
                imageFormat: try c.decodeIfPresent(ImageFormat.self, forKey: .imageFormat) ?? .heic,
                quality: try c.decodeIfPresent(Double.self, forKey: .quality) ?? 0.75,
                maxPixelDimension: try c.decodeIfPresent(Int.self, forKey: .maxPixelDimension) ?? 4096)
    }
  }

  public struct OCRConfig: Codable, Equatable, Sendable {
    public var vendor: String
    public var model: String?
    public var apiKeyEnvironment: String?
    public var concurrency: Int
    public var prompt: String?

    public init(vendor: String, model: String?, apiKeyEnvironment: String?, concurrency: Int, prompt: String?) {
      self.vendor = vendor; self.model = model; self.apiKeyEnvironment = apiKeyEnvironment
      self.concurrency = concurrency; self.prompt = prompt
    }
    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: OCRConfigCodingKeys.self)
      self.init(vendor: try c.decodeIfPresent(String.self, forKey: .vendor) ?? "anthropic",
                model: try decodeOptional(String.self, key: .model, in: c, defaultValue: "claude-sonnet-5-5"),
                apiKeyEnvironment: try decodeOptional(String.self, key: .apiKeyEnvironment, in: c, defaultValue: "ANTHROPIC_API_KEY"),
                concurrency: try c.decodeIfPresent(Int.self, forKey: .concurrency) ?? 2,
                prompt: try decodeOptional(String.self, key: .prompt, in: c, defaultValue: nil))
    }
    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: OCRConfigCodingKeys.self)
      try c.encode(vendor, forKey: .vendor); try c.encode(model, forKey: .model)
      try c.encode(apiKeyEnvironment, forKey: .apiKeyEnvironment); try c.encode(concurrency, forKey: .concurrency)
      try c.encode(prompt, forKey: .prompt)
    }
  }

  public struct AgentConfig: Codable, Equatable, Sendable {
    public var vendor: String
    public var model: String?
    public var apiKeyEnvironment: String?
    public var neighborPages: Int
    public var maxImages: Int
    public var maxContextCharacters: Int
    public var systemPrompt: String?

    public init(vendor: String, model: String?, apiKeyEnvironment: String?, neighborPages: Int, maxImages: Int,
                maxContextCharacters: Int, systemPrompt: String?) {
      self.vendor = vendor; self.model = model; self.apiKeyEnvironment = apiKeyEnvironment
      self.neighborPages = neighborPages; self.maxImages = maxImages; self.maxContextCharacters = maxContextCharacters
      self.systemPrompt = systemPrompt
    }
    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: AgentConfigCodingKeys.self)
      self.init(vendor: try c.decodeIfPresent(String.self, forKey: .vendor) ?? "anthropic",
                model: try decodeOptional(String.self, key: .model, in: c, defaultValue: "claude-opus-5-5"),
                apiKeyEnvironment: try decodeOptional(String.self, key: .apiKeyEnvironment, in: c, defaultValue: "ANTHROPIC_API_KEY"),
                neighborPages: try c.decodeIfPresent(Int.self, forKey: .neighborPages) ?? 1,
                maxImages: try c.decodeIfPresent(Int.self, forKey: .maxImages) ?? 4,
                maxContextCharacters: try c.decodeIfPresent(Int.self, forKey: .maxContextCharacters) ?? 60_000,
                systemPrompt: try decodeOptional(String.self, key: .systemPrompt, in: c, defaultValue: nil))
    }
    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: AgentConfigCodingKeys.self)
      try c.encode(vendor, forKey: .vendor); try c.encode(model, forKey: .model)
      try c.encode(apiKeyEnvironment, forKey: .apiKeyEnvironment); try c.encode(neighborPages, forKey: .neighborPages)
      try c.encode(maxImages, forKey: .maxImages); try c.encode(maxContextCharacters, forKey: .maxContextCharacters)
      try c.encode(systemPrompt, forKey: .systemPrompt)
    }
  }

  public var version: Int
  public var render: RenderConfig
  public var ocr: OCRConfig
  public var agent: AgentConfig
  public static let defaults = StriaConfig(
    version: 1, render: .init(dpi: 150, imageFormat: .heic, quality: 0.75, maxPixelDimension: 4096),
    ocr: .init(vendor: "anthropic", model: "claude-sonnet-5-5", apiKeyEnvironment: "ANTHROPIC_API_KEY", concurrency: 2, prompt: nil),
    agent: .init(vendor: "anthropic", model: "claude-opus-5-5", apiKeyEnvironment: "ANTHROPIC_API_KEY", neighborPages: 1, maxImages: 4, maxContextCharacters: 60_000, systemPrompt: nil)
  )

  public init(version: Int = 1, render: RenderConfig, ocr: OCRConfig, agent: AgentConfig) {
    self.version = version; self.render = render; self.ocr = ocr; self.agent = agent
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: StriaConfigCodingKeys.self)
    let defaults = Self.defaults
    self.init(version: try c.decodeIfPresent(Int.self, forKey: .version) ?? defaults.version,
              render: try c.decodeIfPresent(RenderConfig.self, forKey: .render) ?? defaults.render,
              ocr: try c.decodeIfPresent(OCRConfig.self, forKey: .ocr) ?? defaults.ocr,
              agent: try c.decodeIfPresent(AgentConfig.self, forKey: .agent) ?? defaults.agent)
  }

  public func validate() throws(StriaError) {
    guard version == 1, (72...600).contains(render.dpi), (0.1...1.0).contains(render.quality),
          (1024...8192).contains(render.maxPixelDimension), (1...8).contains(ocr.concurrency),
          (0...5).contains(agent.neighborPages), (1...10).contains(agent.maxImages),
          (1000...500_000).contains(agent.maxContextCharacters) else {
      throw .config("Configuration values are outside their allowed ranges")
    }
    guard KnownVendors.gateway.contains(ocr.vendor) || ocr.vendor == KnownVendors.pdfTextLayer,
          KnownVendors.gateway.contains(agent.vendor) else { throw .config("Unknown vendor") }
    for name in [ocr.apiKeyEnvironment, agent.apiKeyEnvironment].compactMap({ $0 }) {
      guard name.range(of: "^[A-Z_][A-Z0-9_]*$", options: .regularExpression) != nil else {
        throw .config("Invalid apiKeyEnvironment name")
      }
    }
  }

}

private func decodeOptional<T: Decodable, K: CodingKey>(
  _ type: T.Type, key: K, in container: KeyedDecodingContainer<K>, defaultValue: T?
) throws -> T? {
  guard container.contains(key) else { return defaultValue }
  if try container.decodeNil(forKey: key) { return nil }
  return try container.decode(type, forKey: key)
}
