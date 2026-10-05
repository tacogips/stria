import Foundation
import StriaCore
import Testing

@Suite struct VoiceConfigTests {
  @Test func defaultsDecodeOlderConfigurationAndExplicitNullModel() throws {
    let config = try JSONDecoder().decode(StriaConfig.self, from: Data("{}".utf8))
    #expect(config.voice == StriaConfig.VoiceConfig())
    #expect(try ConfigKeyPath.value(of: "voice.engine", in: config) == .string("apple"))
    #expect(try ConfigKeyPath.value(of: "voice.model", in: config) == .null)
    #expect(try ConfigKeyPath.value(of: "voice.language", in: config) == .string("auto"))
    #expect(try ConfigKeyPath.value(of: "voice.autoSend", in: config) == .bool(false))
    #expect(try ConfigKeyPath.value(of: "voice.maxSeconds", in: config) == .int(300))
    let encoded = try JSONEncoder().encode(config)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let voice = try #require(json["voice"] as? [String: Any])
    #expect(voice["model"] is NSNull)
  }

  @Test @MainActor func settingsDraftAndSaveRoundTripVoiceConfiguration() async throws {
    try await withAppModelDataRoot { paths in
      let (library, _) = try makeAppModelFixture(paths: paths, pageTexts: ["page"])
      let settings = SettingsViewModel(library: library, processEnvironment: [:])
      settings.voiceEngine = "gemini"
      settings.voiceModel = "custom-model"
      settings.voiceLanguage = "ja-JP"
      settings.voiceAutoSend = true
      settings.voiceMaxSeconds = 120
      #expect(settings.save())
      settings.voiceEngine = "apple"
      settings.load()
      #expect(settings.voiceEngine == "gemini")
      #expect(settings.voiceModel == "custom-model")
      #expect(settings.voiceLanguage == "ja-JP")
      #expect(settings.voiceAutoSend)
      #expect(settings.voiceMaxSeconds == 120)
      #expect(try ConfigStore.loadOrCreate(paths: paths).voice == library.environment.config.voice)
    }
  }

  @Test func configKeysSetAndValidate() throws {
    for engine in VoiceOptions.engines { #expect(try ConfigKeyPath.setting("voice.engine", to: engine, in: .defaults).voice.engine == engine) }
    for language in ["auto", "en", "ja-JP", "zh-Hans", "zh-Hant-TW", "en-US-u-ca-gregory"] {
      #expect(try ConfigKeyPath.setting("voice.language", to: language, in: .defaults).voice.language == language)
    }
    for (key, value) in [("voice.engine", "anthropic"), ("voice.language", "Japanese"), ("voice.language", "en_US"),
                         ("voice.language", ""), ("voice.maxSeconds", "9"), ("voice.maxSeconds", "1801"), ("voice.autoSend", "maybe")] {
      #expect(throws: StriaError.self) { try ConfigKeyPath.setting(key, to: value, in: .defaults) }
    }
    #expect(try ConfigKeyPath.setting("voice.maxSeconds", to: "10", in: .defaults).voice.maxSeconds == 10)
    #expect(try ConfigKeyPath.setting("voice.maxSeconds", to: "1800", in: .defaults).voice.maxSeconds == 1800)
    #expect(try ConfigKeyPath.setting("voice.model", to: "null", in: .defaults).voice.model == nil)
    #expect(try ConfigKeyPath.setting("voice.autoSend", to: "true", in: .defaults).voice.autoSend)
  }
}
