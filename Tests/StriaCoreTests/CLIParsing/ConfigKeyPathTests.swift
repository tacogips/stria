import StriaCore
import Testing

@Suite struct ConfigKeyPathTests {
  @Test func exposesExactlyFortyFourLeafKeys() throws {
    #expect(ConfigKeyPath.keys.count == 44)
    #expect(Set(ConfigKeyPath.keys) == Set(ConfigKeyPath.credentialKeys + [
      "render.dpi", "render.imageFormat", "render.quality", "render.maxPixelDimension",
      "ocr.vendor", "ocr.model", "ocr.apiKeyEnvironment", "ocr.concurrency", "ocr.prompt", "ocr.timeoutSeconds", "ocr.autoRunOnImport", "ocr.formatRetries",
      "agent.vendor", "agent.model", "agent.apiKeyEnvironment", "agent.neighborPages",
      "agent.maxImages", "agent.maxContextCharacters", "agent.systemPrompt", "agent.timeoutSeconds", "agent.autoSummarize",
      "summary.vendor", "summary.model", "summary.prompt", "summary.language", "summary.autoRunAfterOCR", "summary.timeoutSeconds",
      "sync.enabled", "sync.documents", "sync.ocr", "sync.summaries", "sync.chats", "sync.folder", "sync.intervalMinutes",
      "voice.engine", "voice.model", "voice.language", "voice.autoSend", "voice.maxSeconds"
    ]))
    #expect(try ConfigKeyPath.value(of: "ocr.timeoutSeconds", in: .defaults) == .int(300))
    #expect(try ConfigKeyPath.value(of: "agent.autoSummarize", in: .defaults) == .bool(true))
    #expect(try ConfigKeyPath.setting("agent.autoSummarize", to: "false", in: .defaults).agent.autoSummarize == false)
    #expect(try ConfigKeyPath.value(of: "agent.credentials.openai", in: .defaults) == .string("OPENAI_API_KEY"))
    #expect(try ConfigKeyPath.setting("agent.credentials.openai", to: "MY_KEY", in: .defaults).agent.credentials["openai"] == "MY_KEY")
    #expect(try ConfigKeyPath.setting("agent.credentials.openai", to: "null", in: .defaults).agent.credentials["openai"] == nil)
    #expect(throws: StriaError.self) { try ConfigKeyPath.setting("agent.credentials.openai", to: "sk-bad", in: .defaults) }
    #expect(throws: StriaError.self) { try ConfigKeyPath.value(of: "agent.credentials.claude-code", in: .defaults) }
    #expect(try ConfigKeyPath.setting("agent.timeoutSeconds", to: "900", in: .defaults).agent.timeoutSeconds == 900)
    #expect(throws: StriaError.self) { try ConfigKeyPath.setting("agent.timeoutSeconds", to: "5", in: .defaults) }
    #expect(try ConfigKeyPath.value(of: "ocr.model", in: .defaults) == .null)
    #expect(try ConfigKeyPath.value(of: "ocr.vendor", in: .defaults) == .null)
    #expect(try ConfigKeyPath.value(of: "ocr.model", in: .testing) == .string("test-ocr-model"))
    #expect(try ConfigKeyPath.setting("ocr.autoRunOnImport", to: "false", in: .defaults).ocr.autoRunOnImport == false)
    #expect(try ConfigKeyPath.setting("agent.vendor", to: "null", in: .testing).agent.vendor == nil)
    #expect(throws: StriaError.self) { try ConfigKeyPath.setting("ocr.autoRunOnImport", to: "maybe", in: .defaults) }
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
