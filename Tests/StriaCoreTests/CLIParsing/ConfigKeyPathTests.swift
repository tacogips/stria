import StriaCore
import Testing

@Suite struct ConfigKeyPathTests {
  @Test func exposesExactlySixteenLeafKeys() throws {
    #expect(ConfigKeyPath.keys.count == 16)
    #expect(Set(ConfigKeyPath.keys) == Set([
      "render.dpi", "render.imageFormat", "render.quality", "render.maxPixelDimension",
      "ocr.vendor", "ocr.model", "ocr.apiKeyEnvironment", "ocr.concurrency", "ocr.prompt",
      "agent.vendor", "agent.model", "agent.apiKeyEnvironment", "agent.neighborPages",
      "agent.maxImages", "agent.maxContextCharacters", "agent.systemPrompt"
    ]))
    let model = try ConfigKeyPath.value(of: "ocr.model", in: .defaults)
    #expect(model == .string("claude-sonnet-5-5"))
  }

  @Test func setsAndValidatesValues() throws {
    let concurrency = try ConfigKeyPath.setting("ocr.concurrency", to: "4", in: .defaults)
    let clearedModel = try ConfigKeyPath.setting("agent.model", to: "null", in: .defaults)
    let localVendor = try ConfigKeyPath.setting("ocr.vendor", to: "pdf-text-layer", in: .defaults)
    let cursorVendor = try ConfigKeyPath.setting("ocr.vendor", to: "cursor-api", in: .defaults)
    #expect(concurrency.ocr.concurrency == 4)
    #expect(clearedModel.agent.model == nil)
    #expect(localVendor.ocr.vendor == "pdf-text-layer")
    #expect(cursorVendor.ocr.vendor == "cursor-api")
    for (key, raw) in [("ocr.concurrency", "9"), ("render.imageFormat", "png"), ("render.dpi", "null"),
                       ("ocr.apiKeyEnvironment", "sk-live-abc"), ("agent.vendor", "pdf-text-layer"), ("missing.key", "x")] {
      do {
        _ = try ConfigKeyPath.setting(key, to: raw, in: .defaults)
        Issue.record("Expected usageError for \(key)=\(raw)")
      } catch {
        #expect(error.code == .usageError)
      }
    }
  }

  @Test func rejectsUnknownValueLookup() {
    do {
      _ = try ConfigKeyPath.value(of: "nope", in: .defaults)
      Issue.record("Expected unknown key lookup to fail")
    } catch {
      #expect(error.code == .usageError)
    }
  }

  @Test func nullClearsNullableStringValues() throws {
    var config = try ConfigKeyPath.setting("ocr.apiKeyEnvironment", to: "TEST_API_KEY", in: .defaults)
    config = try ConfigKeyPath.setting("ocr.prompt", to: "prompt", in: config)
    config = try ConfigKeyPath.setting("agent.systemPrompt", to: "system prompt", in: config)
    config = try ConfigKeyPath.setting("ocr.apiKeyEnvironment", to: "null", in: config)
    config = try ConfigKeyPath.setting("ocr.prompt", to: "null", in: config)
    config = try ConfigKeyPath.setting("agent.systemPrompt", to: "null", in: config)
    #expect(config.ocr.apiKeyEnvironment == nil)
    #expect(config.ocr.prompt == nil)
    #expect(config.agent.systemPrompt == nil)
  }
}
