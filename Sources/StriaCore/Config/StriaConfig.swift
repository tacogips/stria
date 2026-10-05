import Foundation

public enum KnownVendors {
  public static let platformUnavailableReason = "Runs a local CLI; only available on the Mac"

  public static func isAvailableOnThisPlatform(_ vendor: String, platform: StriaPlatform = .current) -> Bool {
    platform == .macOS || !cliVendors.contains(vendor)
  }

  public static var selectable: [String] { selectable(on: .current) }

  public static func selectable(on platform: StriaPlatform) -> [String] {
    gateway.filter { isAvailableOnThisPlatform($0, platform: platform) }
  }

  public static func requireAvailable(_ vendor: String, platform: StriaPlatform = .current) throws(StriaError) {
    guard isAvailableOnThisPlatform(vendor, platform: platform) else {
      throw .serviceUnavailable(platformUnavailableReason)
    }
  }

  public static let gateway = ["claude-code", "codex", "cursor", "cursor-api", "openai", "anthropic", "gemini", "openrouter"]
  public static let pdfTextLayer = "pdf-text-layer"
  public static let apiKeyVendors: Set<String> = ["openai", "anthropic", "gemini", "openrouter", "cursor-api"]
  /// Vendors that run as local agents with tools (they can execute `stria`).
  public static let cliVendors: Set<String> = ["claude-code", "codex", "cursor"]
}

private enum RenderConfigCodingKeys: String, CodingKey { case dpi, imageFormat, quality, maxPixelDimension }
private enum OCRConfigCodingKeys: String, CodingKey {
  case vendor, model, apiKeyEnvironment, concurrency, prompt, timeoutSeconds, autoRunOnImport, formatRetries
}
private enum AgentConfigCodingKeys: String, CodingKey {
  case vendor, model, apiKeyEnvironment, neighborPages, maxImages, maxContextCharacters, systemPrompt, timeoutSeconds, credentials,
    autoSummarize
}
private enum StriaConfigCodingKeys: String, CodingKey { case version, render, ocr, agent, summary }

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
    /// nil means not configured: no OCR runs and nothing is called until the
    /// user picks a vendor (Settings in the app, `stria config set` in the CLI).
    public var vendor: String?
    public var model: String?
    public var apiKeyEnvironment: String?
    public var concurrency: Int
    public var prompt: String?
    /// Upper bound for one page's model call.
    public var timeoutSeconds: Int
    /// Whether an import OCRs its pages right away, or waits for "Run OCR".
    public var autoRunOnImport: Bool
    /// How often a reply that is not the `{"body", "tags"}` JSON object is
    /// asked again (with backoff) before the page fails.
    public var formatRetries: Int

    public var isConfigured: Bool { vendor != nil }

    public init(vendor: String?, model: String?, apiKeyEnvironment: String?, concurrency: Int, prompt: String?,
                timeoutSeconds: Int = 300, autoRunOnImport: Bool = true, formatRetries: Int = OCRDefaults.formatRetries) {
      self.vendor = vendor; self.model = model; self.apiKeyEnvironment = apiKeyEnvironment
      self.concurrency = concurrency; self.prompt = prompt; self.timeoutSeconds = timeoutSeconds
      self.autoRunOnImport = autoRunOnImport; self.formatRetries = formatRetries
    }
    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: OCRConfigCodingKeys.self)
      self.init(vendor: try decodeOptional(String.self, key: .vendor, in: c, defaultValue: nil),
                model: try decodeOptional(String.self, key: .model, in: c, defaultValue: nil),
                apiKeyEnvironment: try decodeOptional(String.self, key: .apiKeyEnvironment, in: c, defaultValue: nil),
                concurrency: try c.decodeIfPresent(Int.self, forKey: .concurrency) ?? 2,
                prompt: try decodeOptional(String.self, key: .prompt, in: c, defaultValue: nil),
                timeoutSeconds: try c.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 300,
                autoRunOnImport: try c.decodeIfPresent(Bool.self, forKey: .autoRunOnImport) ?? true,
                formatRetries: try c.decodeIfPresent(Int.self, forKey: .formatRetries) ?? OCRDefaults.formatRetries)
    }
    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: OCRConfigCodingKeys.self)
      try c.encode(vendor, forKey: .vendor); try c.encode(model, forKey: .model)
      try c.encode(apiKeyEnvironment, forKey: .apiKeyEnvironment); try c.encode(concurrency, forKey: .concurrency)
      try c.encode(prompt, forKey: .prompt); try c.encode(timeoutSeconds, forKey: .timeoutSeconds)
      try c.encode(autoRunOnImport, forKey: .autoRunOnImport); try c.encode(formatRetries, forKey: .formatRetries)
    }
  }

  public struct AgentConfig: Codable, Equatable, Sendable {
    /// nil means not configured: asking fails as unavailable until the user picks a vendor.
    public var vendor: String?
    public var model: String?
    public var apiKeyEnvironment: String?
    public var neighborPages: Int
    public var maxImages: Int
    public var maxContextCharacters: Int
    public var systemPrompt: String?
    /// Upper bound for one question's model call.
    public var timeoutSeconds: Int
    /// API key environment variable name per API vendor. The chat picks the
    /// vendor and model per question; this is the only per-vendor setting.
    public var credentials: [String: String]
    /// Refresh a conversation's summary after each answer (one extra call).
    public var autoSummarize: Bool

    public static let defaultCredentials = [
      "anthropic": "ANTHROPIC_API_KEY", "openai": "OPENAI_API_KEY", "gemini": "GEMINI_API_KEY",
      "openrouter": "OPENROUTER_API_KEY", "cursor-api": "CURSOR_API_KEY"
    ]

    public var isConfigured: Bool { vendor != nil }

    /// The credential variable for a vendor: the per-vendor table, else the
    /// legacy single `apiKeyEnvironment` when it belongs to that vendor.
    public func credential(for vendor: String) -> String? {
      if let name = credentials[vendor], !name.isEmpty { return name }
      return self.vendor == vendor ? apiKeyEnvironment : nil
    }

    public init(vendor: String?, model: String?, apiKeyEnvironment: String?, neighborPages: Int, maxImages: Int,
                maxContextCharacters: Int, systemPrompt: String?, timeoutSeconds: Int = 600,
                credentials: [String: String] = AgentConfig.defaultCredentials, autoSummarize: Bool = true) {
      self.vendor = vendor; self.model = model; self.apiKeyEnvironment = apiKeyEnvironment
      self.neighborPages = neighborPages; self.maxImages = maxImages; self.maxContextCharacters = maxContextCharacters
      self.systemPrompt = systemPrompt; self.timeoutSeconds = timeoutSeconds; self.credentials = credentials
      self.autoSummarize = autoSummarize
    }
    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: AgentConfigCodingKeys.self)
      self.init(vendor: try decodeOptional(String.self, key: .vendor, in: c, defaultValue: nil),
                model: try decodeOptional(String.self, key: .model, in: c, defaultValue: nil),
                apiKeyEnvironment: try decodeOptional(String.self, key: .apiKeyEnvironment, in: c, defaultValue: nil),
                neighborPages: try c.decodeIfPresent(Int.self, forKey: .neighborPages) ?? 1,
                maxImages: try c.decodeIfPresent(Int.self, forKey: .maxImages) ?? 4,
                maxContextCharacters: try c.decodeIfPresent(Int.self, forKey: .maxContextCharacters) ?? 60_000,
                systemPrompt: try decodeOptional(String.self, key: .systemPrompt, in: c, defaultValue: nil),
                timeoutSeconds: try c.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 600,
                credentials: try c.decodeIfPresent([String: String].self, forKey: .credentials) ?? AgentConfig.defaultCredentials,
                autoSummarize: try c.decodeIfPresent(Bool.self, forKey: .autoSummarize) ?? true)
    }
    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: AgentConfigCodingKeys.self)
      try c.encode(vendor, forKey: .vendor); try c.encode(model, forKey: .model)
      try c.encode(apiKeyEnvironment, forKey: .apiKeyEnvironment); try c.encode(neighborPages, forKey: .neighborPages)
      try c.encode(maxImages, forKey: .maxImages); try c.encode(maxContextCharacters, forKey: .maxContextCharacters)
      try c.encode(systemPrompt, forKey: .systemPrompt); try c.encode(timeoutSeconds, forKey: .timeoutSeconds)
      try c.encode(credentials, forKey: .credentials); try c.encode(autoSummarize, forKey: .autoSummarize)
    }
  }

  public var version: Int
  public var render: RenderConfig
  public var ocr: OCRConfig
  public var agent: AgentConfig
  public var summary: SummaryConfig
  public static let defaults = StriaConfig(
    version: 1, render: .init(dpi: 150, imageFormat: .heic, quality: 0.75, maxPixelDimension: 4096),
    ocr: .init(vendor: nil, model: nil, apiKeyEnvironment: nil, concurrency: 2, prompt: nil),
    agent: .init(vendor: nil, model: nil, apiKeyEnvironment: nil, neighborPages: 1, maxImages: 4, maxContextCharacters: 60_000, systemPrompt: nil)
  )

  public init(version: Int = 1, render: RenderConfig, ocr: OCRConfig, agent: AgentConfig, summary: SummaryConfig = SummaryConfig()) {
    self.version = version; self.render = render; self.ocr = ocr; self.agent = agent; self.summary = summary
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: StriaConfigCodingKeys.self)
    let defaults = Self.defaults
    self.init(version: try c.decodeIfPresent(Int.self, forKey: .version) ?? defaults.version,
              render: try c.decodeIfPresent(RenderConfig.self, forKey: .render) ?? defaults.render,
              ocr: try c.decodeIfPresent(OCRConfig.self, forKey: .ocr) ?? defaults.ocr,
              agent: try c.decodeIfPresent(AgentConfig.self, forKey: .agent) ?? defaults.agent,
              summary: try c.decodeIfPresent(SummaryConfig.self, forKey: .summary) ?? defaults.summary)
  }

  public func validate() throws(StriaError) {
    guard version == 1 else { throw .config("Unsupported config version \(version)") }
    guard (72...600).contains(render.dpi), (0.1...1.0).contains(render.quality),
          (1024...8192).contains(render.maxPixelDimension), (1...8).contains(ocr.concurrency),
          (0...5).contains(agent.neighborPages), (1...10).contains(agent.maxImages),
          (1000...500_000).contains(agent.maxContextCharacters),
          (10...3600).contains(ocr.timeoutSeconds), (10...3600).contains(agent.timeoutSeconds),
          (0...5).contains(ocr.formatRetries) else {
      throw .config("Configuration values are outside their allowed ranges")
    }
    if let vendor = ocr.vendor, !KnownVendors.gateway.contains(vendor), vendor != KnownVendors.pdfTextLayer {
      throw .config("Unknown OCR vendor '\(vendor)'")
    }
    if let vendor = agent.vendor, !KnownVendors.gateway.contains(vendor) {
      throw .config("Unknown agent vendor '\(vendor)'")
    }
    try summary.validate()
    for name in [ocr.apiKeyEnvironment, agent.apiKeyEnvironment].compactMap({ $0 }) + Array(agent.credentials.values) {
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
