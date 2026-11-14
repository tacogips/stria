import Foundation

public enum ConfigKeyPath {
  public static let credentialKeys = KnownVendors.apiKeyVendors.sorted().map { "agent.credentials.\($0)" }
  public static let keys = credentialKeys + [
    "agent.apiKeyEnvironment", "agent.maxContextCharacters", "agent.maxImages", "agent.model",
    "agent.neighborPages", "agent.systemPrompt", "agent.timeoutSeconds", "agent.vendor", "ocr.apiKeyEnvironment",
    "ocr.autoRunOnImport", "ocr.concurrency", "ocr.model", "ocr.prompt", "ocr.timeoutSeconds", "ocr.vendor", "render.dpi",
    "render.imageFormat", "render.maxPixelDimension", "render.quality"
  ]

  public static func value(of key: String, in config: StriaConfig) throws(StriaError) -> JSONValue {
    if let vendor = credentialVendor(key) { return config.agent.credentials[vendor].map(JSONValue.string) ?? .null }
    switch key {
    case "render.dpi": return .int(config.render.dpi)
    case "render.imageFormat": return .string(config.render.imageFormat.rawValue)
    case "render.quality": return .double(config.render.quality)
    case "render.maxPixelDimension": return .int(config.render.maxPixelDimension)
    case "ocr.vendor": return config.ocr.vendor.map(JSONValue.string) ?? .null
    case "ocr.autoRunOnImport": return .bool(config.ocr.autoRunOnImport)
    case "ocr.model": return config.ocr.model.map(JSONValue.string) ?? .null
    case "ocr.apiKeyEnvironment": return config.ocr.apiKeyEnvironment.map(JSONValue.string) ?? .null
    case "ocr.concurrency": return .int(config.ocr.concurrency)
    case "ocr.prompt": return config.ocr.prompt.map(JSONValue.string) ?? .null
    case "ocr.timeoutSeconds": return .int(config.ocr.timeoutSeconds)
    case "agent.timeoutSeconds": return .int(config.agent.timeoutSeconds)
    case "agent.vendor": return config.agent.vendor.map(JSONValue.string) ?? .null
    case "agent.model": return config.agent.model.map(JSONValue.string) ?? .null
    case "agent.apiKeyEnvironment": return config.agent.apiKeyEnvironment.map(JSONValue.string) ?? .null
    case "agent.neighborPages": return .int(config.agent.neighborPages)
    case "agent.maxImages": return .int(config.agent.maxImages)
    case "agent.maxContextCharacters": return .int(config.agent.maxContextCharacters)
    case "agent.systemPrompt": return config.agent.systemPrompt.map(JSONValue.string) ?? .null
    default: throw .usage("Unknown config key '\(key)'")
    }
  }

  private static func credentialVendor(_ key: String) -> String? {
    guard key.hasPrefix("agent.credentials.") else { return nil }
    let vendor = String(key.dropFirst("agent.credentials.".count))
    return KnownVendors.apiKeyVendors.contains(vendor) ? vendor : nil
  }

  public static func setting(_ key: String, to raw: String, in config: StriaConfig) throws(StriaError) -> StriaConfig {
    guard keys.contains(key) else { throw .usage("Unknown config key '\(key)'") }
    var updated = config
    if raw == "null" {
      try clear(key, in: &updated)
    } else if key.hasPrefix("render.") {
      try setRender(key, raw, in: &updated)
    } else if key.hasPrefix("ocr.") {
      try setOCR(key, raw, in: &updated)
    } else {
      try setAgent(key, raw, in: &updated)
    }
    do {
      try updated.validate()
    } catch {
      throw .usage(error.message)
    }
    return updated
  }

  private static func clear(_ key: String, in updated: inout StriaConfig) throws(StriaError) {
    switch key {
    case "ocr.vendor": updated.ocr.vendor = nil
    case "agent.vendor": updated.agent.vendor = nil
    case "ocr.model": updated.ocr.model = nil
    case "ocr.apiKeyEnvironment": updated.ocr.apiKeyEnvironment = nil
    case "ocr.prompt": updated.ocr.prompt = nil
    case "agent.model": updated.agent.model = nil
    case "agent.apiKeyEnvironment": updated.agent.apiKeyEnvironment = nil
    case "agent.systemPrompt": updated.agent.systemPrompt = nil
    default:
      if let vendor = credentialVendor(key) { updated.agent.credentials[vendor] = nil } else { throw .usage("Config key '\(key)' cannot be null") }
    }
  }

  private static func setRender(_ key: String, _ raw: String, in updated: inout StriaConfig) throws(StriaError) {
    switch key {
    case "render.dpi": updated.render.dpi = try integer(raw, key: key)
    case "render.imageFormat":
      guard let format = ImageFormat(rawValue: raw), [ImageFormat.heic, .jpeg].contains(format) else {
        throw .usage("render.imageFormat must be heic or jpeg")
      }
      updated.render.imageFormat = format
    case "render.quality": updated.render.quality = try number(raw, key: key)
    case "render.maxPixelDimension": updated.render.maxPixelDimension = try integer(raw, key: key)
    default: throw .usage("Unknown config key '\(key)'")
    }
  }

  private static func setOCR(_ key: String, _ raw: String, in updated: inout StriaConfig) throws(StriaError) {
    switch key {
    case "ocr.vendor": updated.ocr.vendor = raw
    case "ocr.model": updated.ocr.model = raw
    case "ocr.apiKeyEnvironment": updated.ocr.apiKeyEnvironment = raw
    case "ocr.concurrency": updated.ocr.concurrency = try integer(raw, key: key)
    case "ocr.autoRunOnImport": updated.ocr.autoRunOnImport = try boolean(raw, key: key)
    case "ocr.prompt": updated.ocr.prompt = raw
    case "ocr.timeoutSeconds": updated.ocr.timeoutSeconds = try integer(raw, key: key)
    default: throw .usage("Unknown config key '\(key)'")
    }
  }

  private static func setAgent(_ key: String, _ raw: String, in updated: inout StriaConfig) throws(StriaError) {
    switch key {
    case "agent.vendor": updated.agent.vendor = raw
    case "agent.model": updated.agent.model = raw
    case "agent.apiKeyEnvironment": updated.agent.apiKeyEnvironment = raw
    case "agent.neighborPages": updated.agent.neighborPages = try integer(raw, key: key)
    case "agent.maxImages": updated.agent.maxImages = try integer(raw, key: key)
    case "agent.maxContextCharacters": updated.agent.maxContextCharacters = try integer(raw, key: key)
    case "agent.systemPrompt": updated.agent.systemPrompt = raw
    case "agent.timeoutSeconds": updated.agent.timeoutSeconds = try integer(raw, key: key)
    default:
      if let vendor = credentialVendor(key) { updated.agent.credentials[vendor] = raw } else { throw .usage("Unknown config key '\(key)'") }
    }
  }

  private static func integer(_ raw: String, key: String) throws(StriaError) -> Int {
    guard let value = Int(raw), String(value) == raw else { throw .usage("Config key '\(key)' requires an integer") }
    return value
  }

  private static func boolean(_ raw: String, key: String) throws(StriaError) -> Bool {
    switch raw.lowercased() {
    case "true", "yes", "on", "1": return true
    case "false", "no", "off", "0": return false
    default: throw .usage("Config key '\(key)' requires true or false")
    }
  }

  private static func number(_ raw: String, key: String) throws(StriaError) -> Double {
    guard let value = Double(raw), value.isFinite else { throw .usage("Config key '\(key)' requires a number") }
    return value
  }
}
