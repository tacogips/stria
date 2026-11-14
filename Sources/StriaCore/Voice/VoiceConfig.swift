import Foundation

private enum VoiceConfigCodingKeys: String, CodingKey { case engine, model, language, autoSend, maxSeconds }

public extension StriaConfig {
  struct VoiceConfig: Codable, Equatable, Sendable {
    public var engine: String
    public var model: String?
    public var language: String
    public var autoSend: Bool
    public var maxSeconds: Int

    public init(engine: String = "apple", model: String? = nil, language: String = "auto",
                autoSend: Bool = false, maxSeconds: Int = 300) {
      self.engine = engine; self.model = model; self.language = language
      self.autoSend = autoSend; self.maxSeconds = maxSeconds
    }

    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: VoiceConfigCodingKeys.self)
      self.init(engine: try c.decodeIfPresent(String.self, forKey: .engine) ?? "apple",
                model: try c.decodeIfPresent(String.self, forKey: .model),
                language: try c.decodeIfPresent(String.self, forKey: .language) ?? "auto",
                autoSend: try c.decodeIfPresent(Bool.self, forKey: .autoSend) ?? false,
                maxSeconds: try c.decodeIfPresent(Int.self, forKey: .maxSeconds) ?? 300)
    }

    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: VoiceConfigCodingKeys.self)
      try c.encode(engine, forKey: .engine); try c.encode(model, forKey: .model)
      try c.encode(language, forKey: .language); try c.encode(autoSend, forKey: .autoSend)
      try c.encode(maxSeconds, forKey: .maxSeconds)
    }

    func validate() throws(StriaError) {
      guard VoiceOptions.engines.contains(engine) else { throw .config("Unknown voice engine '\(engine)'") }
      guard (10...1800).contains(maxSeconds) else { throw .config("voice.maxSeconds must be 10...1800") }
      guard language == "auto" || (language.count <= 64 && language.range(
        of: "^[A-Za-z]{2,3}(-[A-Za-z0-9]{1,8})*$", options: .regularExpression) != nil) else {
        throw .config("voice.language must be auto or a BCP-47 language tag")
      }
    }
  }
}

public enum VoiceOptions {
  public static let engines = ["apple", "openai", "gemini", "openrouter"]
  public static let languages = ["auto", "en-US", "ja-JP", "zh-CN", "zh-TW", "ko-KR", "fr-FR", "de-DE", "es-ES"]

  public static func engineName(_ engine: String) -> String {
    switch engine {
    case "apple": "Apple on-device"
    case "openai": "OpenAI"
    case "gemini": "Gemini"
    case "openrouter": "OpenRouter"
    default: engine
    }
  }

  public static func languageName(_ language: String) -> String {
    switch language {
    case "auto": "Auto"
    case "en-US": "English"
    case "ja-JP": "Japanese"
    case "zh-CN", "zh-Hans": "Chinese (Simplified)"
    case "zh-TW", "zh-Hant": "Chinese (Traditional)"
    case "ko-KR": "Korean"
    case "fr-FR": "French"
    case "de-DE": "German"
    case "es-ES": "Spanish"
    default: language
    }
  }

  public static func privacy(_ engine: String) -> String {
    if engine != "apple" { return "Audio is sent to \(engineName(engine)) after recording stops. Temporary audio is deleted afterwards." }
    return "Apple recognition runs on device on macOS 26 / iOS 26. Earlier systems use on-device recognition when supported; otherwise audio is sent to Apple."
  }
}
