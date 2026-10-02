import Foundation

public enum ConfigKeyPath {
  public static let keys = [
    "agent.apiKeyEnvironment", "agent.maxContextCharacters", "agent.maxImages", "agent.model",
    "agent.neighborPages", "agent.systemPrompt", "agent.timeoutSeconds", "agent.vendor", "ocr.apiKeyEnvironment",
    "ocr.concurrency", "ocr.model", "ocr.prompt", "ocr.timeoutSeconds", "ocr.vendor", "render.dpi",
    "render.imageFormat", "render.maxPixelDimension", "render.quality"
  ]

  public static func value(of key: String, in config: StriaConfig) throws(StriaError) -> JSONValue {
    switch key {
    case "render.dpi": .int(config.render.dpi)
    case "render.imageFormat": .string(config.render.imageFormat.rawValue)
    case "render.quality": .double(config.render.quality)
    case "render.maxPixelDimension": .int(config.render.maxPixelDimension)
    case "ocr.vendor": .string(config.ocr.vendor)
    case "ocr.model": config.ocr.model.map(JSONValue.string) ?? .null
    case "ocr.apiKeyEnvironment": config.ocr.apiKeyEnvironment.map(JSONValue.string) ?? .null
    case "ocr.concurrency": .int(config.ocr.concurrency)
    case "ocr.prompt": config.ocr.prompt.map(JSONValue.string) ?? .null
    case "ocr.timeoutSeconds": .int(config.ocr.timeoutSeconds)
    case "agent.timeoutSeconds": .int(config.agent.timeoutSeconds)
    case "agent.vendor": .string(config.agent.vendor)
    case "agent.model": config.agent.model.map(JSONValue.string) ?? .null
    case "agent.apiKeyEnvironment": config.agent.apiKeyEnvironment.map(JSONValue.string) ?? .null
    case "agent.neighborPages": .int(config.agent.neighborPages)
    case "agent.maxImages": .int(config.agent.maxImages)
    case "agent.maxContextCharacters": .int(config.agent.maxContextCharacters)
    case "agent.systemPrompt": config.agent.systemPrompt.map(JSONValue.string) ?? .null
    default: throw .usage("Unknown config key '\(key)'")
    }
  }

  public static func setting(_ key: String, to raw: String, in config: StriaConfig) throws(StriaError) -> StriaConfig {
    guard keys.contains(key) else { throw .usage("Unknown config key '\(key)'") }
    var updated = config
    if raw == "null" {
      switch key {
      case "ocr.model": updated.ocr.model = nil
      case "ocr.apiKeyEnvironment": updated.ocr.apiKeyEnvironment = nil
      case "ocr.prompt": updated.ocr.prompt = nil
      case "agent.model": updated.agent.model = nil
      case "agent.apiKeyEnvironment": updated.agent.apiKeyEnvironment = nil
      case "agent.systemPrompt": updated.agent.systemPrompt = nil
      default: throw .usage("Config key '\(key)' cannot be null")
      }
    } else {
      switch key {
      case "render.dpi": updated.render.dpi = try integer(raw, key: key)
      case "render.imageFormat":
        guard let format = ImageFormat(rawValue: raw), [ImageFormat.heic, .jpeg].contains(format) else {
          throw .usage("render.imageFormat must be heic or jpeg")
        }
        updated.render.imageFormat = format
      case "render.quality": updated.render.quality = try number(raw, key: key)
      case "render.maxPixelDimension": updated.render.maxPixelDimension = try integer(raw, key: key)
      case "ocr.vendor": updated.ocr.vendor = raw
      case "ocr.model": updated.ocr.model = raw
      case "ocr.apiKeyEnvironment": updated.ocr.apiKeyEnvironment = raw
      case "ocr.concurrency": updated.ocr.concurrency = try integer(raw, key: key)
      case "ocr.prompt": updated.ocr.prompt = raw
      case "ocr.timeoutSeconds": updated.ocr.timeoutSeconds = try integer(raw, key: key)
      case "agent.timeoutSeconds": updated.agent.timeoutSeconds = try integer(raw, key: key)
      case "agent.vendor": updated.agent.vendor = raw
      case "agent.model": updated.agent.model = raw
      case "agent.apiKeyEnvironment": updated.agent.apiKeyEnvironment = raw
      case "agent.neighborPages": updated.agent.neighborPages = try integer(raw, key: key)
      case "agent.maxImages": updated.agent.maxImages = try integer(raw, key: key)
      case "agent.maxContextCharacters": updated.agent.maxContextCharacters = try integer(raw, key: key)
      case "agent.systemPrompt": updated.agent.systemPrompt = raw
      default: throw .usage("Unknown config key '\(key)'")
      }
    }
    do {
      try updated.validate()
    } catch {
      throw .usage(error.message)
    }
    return updated
  }

  private static func integer(_ raw: String, key: String) throws(StriaError) -> Int {
    guard let value = Int(raw), String(value) == raw else { throw .usage("Config key '\(key)' requires an integer") }
    return value
  }

  private static func number(_ raw: String, key: String) throws(StriaError) -> Double {
    guard let value = Double(raw), value.isFinite else { throw .usage("Config key '\(key)' requires a number") }
    return value
  }
}
