import AgentGateway
import AgentGatewayAppCore
import Foundation
import StriaCore
import Testing

actor FakeTranscriber: GatewayTranscribing {
  var received: GatewayTranscriptionParams?
  var failure: String?
  func fail(_ message: String) { failure = message }
  func transcribe(_ params: GatewayTranscriptionParams) async throws -> GatewayTranscriptionResult {
    received = params
    if let failure { throw SpeechInputError(failure) }
    return GatewayTranscriptionResult(vendor: params.vendor, model: params.model, text: "transcript")
  }
}

@MainActor
final class FakeVoiceRecorder: VoiceAudioRecording {
  var file: URL?
  var stopped = false
  func start(in cache: URL, onLevel: @escaping @MainActor @Sendable (Float) -> Void) throws -> URL {
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let url = cache.appendingPathComponent("fake.m4a")
    try Data([1, 2, 3]).write(to: url)
    file = url; onLevel(0.5)
    return url
  }
  func stop() throws { stopped = true }
  func cancel() { if let file { try? FileManager.default.removeItem(at: file) } }
}

@Suite @MainActor struct VendorSpeechEngineTests {
  @Test func mappingUsesGatewayDefaultsAndLanguageAndCredentialTable() async throws {
    for engineName in ["openai", "gemini", "openrouter"] {
      try await withAppModelDataRoot { paths in
        var config = StriaConfig.defaults
        config.voice.engine = engineName
        config.voice.language = "ja-JP"
        config.agent.credentials[engineName] = "CUSTOM_VOICE_KEY"
        let gateway = FakeTranscriber()
        let recorder = FakeVoiceRecorder()
        let engine = try VendorSpeechEngine(config: config, cache: paths.cache,
          credentialEnvironment: CredentialEnvironment(environment: [:]), gateway: gateway, recorder: recorder, permission: {})
        try await engine.requestPermission()
        try await engine.start(language: "ja-JP") { _ in }
        #expect(try await engine.stop() == "transcript")
        let params = try #require(await gateway.received)
        let vendor = try #require(GatewayVendor(rawValue: engineName))
        #expect(params.model == GatewayTranscriptionModels.defaults[vendor]?.first)
        #expect(params.language == "ja")
        #expect(params.apiKeyEnvironment == "CUSTOM_VOICE_KEY")
        #expect(params.mimeType == "audio/mp4")
        #expect(params.audioFile.pathExtension == "m4a")
        #expect(recorder.stopped)
        #expect(!FileManager.default.fileExists(atPath: params.audioFile.path))
      }
    }
  }

  @Test func autoLanguageIsOmittedAndCustomModelIsPreserved() throws {
    var config = StriaConfig.defaults
    config.voice.engine = "openai"
    config.voice.model = "custom-model"
    let params = try VendorSpeechEngine.parameters(config: config, audioFile: URL(fileURLWithPath: "/tmp/fake.m4a"))
    #expect(params.language == nil)
    #expect(params.model == "custom-model")
  }

  @Test func unsupportedVendorsAreRejectedBeforeRecording() throws {
    for vendor in ["apple", "anthropic", "cursor-api", "codex"] {
      var config = StriaConfig.defaults
      config.voice.engine = vendor
      #expect(throws: SpeechInputError.self) {
        try VendorSpeechEngine(config: config, cache: URL(fileURLWithPath: "/tmp"),
                              credentialEnvironment: CredentialEnvironment(environment: [:]), gateway: FakeTranscriber(), recorder: FakeVoiceRecorder(), permission: {})
      }
      #expect(VendorSpeechEngine.modelOptions(for: vendor).isEmpty)
    }
  }

  @Test func credentialEnvironmentUsesPlatformStoreAndConfiguredVariable() throws {
    let store = InMemoryCredentialStore()
    store.write("saved-test-key", vendor: "openai")
    var config = StriaConfig.defaults
    config.voice.engine = "openai"
    config.agent.credentials["openai"] = "VOICE_TEST_KEY"
    for platform in [StriaPlatform.macOS, .iOS] {
      var received: [String: String] = [:]
      _ = try VendorSpeechEngine(config: config, cache: URL(fileURLWithPath: "/tmp"),
        credentialEnvironment: CredentialEnvironment(environment: ["VOICE_TEST_KEY": "process-test-key"], platform: platform, store: store),
        makeGateway: { received = $0; return FakeTranscriber() }, recorder: FakeVoiceRecorder(), permission: {})
      #expect(received["VOICE_TEST_KEY"] == (platform == .iOS ? "saved-test-key" : "process-test-key"))
      #expect(received["OPENAI_API_KEY"] == nil)
    }
  }

  @Test func vendorFailureDeletesAudioAndRedactsCredentialValue() async throws {
    try await withAppModelDataRoot { paths in
      var config = StriaConfig.defaults
      config.voice.engine = "openai"
      let gateway = FakeTranscriber()
      await gateway.fail("rejected dummy-secret")
      let recorder = FakeVoiceRecorder()
      let engine = try VendorSpeechEngine(config: config, cache: paths.cache,
        credentialEnvironment: CredentialEnvironment(environment: ["OPENAI_API_KEY": "dummy-secret"]),
        gateway: gateway, recorder: recorder, permission: {})
      try await engine.start(language: "auto") { _ in }
      let file = try #require(recorder.file)
      await #expect(throws: SpeechInputError("rejected [REDACTED]")) { try await engine.stop() }
      #expect(!FileManager.default.fileExists(atPath: file.path))
    }
  }

  @Test func cancelDeletesTemporaryAudio() async throws {
    try await withAppModelDataRoot { paths in
      var config = StriaConfig.defaults
      config.voice.engine = "openai"
      let recorder = FakeVoiceRecorder()
      let engine = try VendorSpeechEngine(config: config, cache: paths.cache, credentialEnvironment: CredentialEnvironment(environment: [:]),
                                         gateway: FakeTranscriber(), recorder: recorder, permission: {})
      try await engine.start(language: "auto") { _ in }
      let file = try #require(recorder.file)
      engine.cancel()
      #expect(!FileManager.default.fileExists(atPath: file.path))
    }
  }
}
