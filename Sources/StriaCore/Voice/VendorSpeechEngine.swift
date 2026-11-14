import AgentGateway
import AgentGatewayAppCore
import Foundation

@MainActor
public final class VendorSpeechEngine: SpeechTranscriptionEngine {
  private let config: StriaConfig
  private let cache: URL
  private let gateway: any GatewayTranscribing
  private let recorder: any VoiceAudioRecording
  private let permission: @MainActor () async throws -> Void
  private let secrets: [String]
  private var file: URL?

  public init(config: StriaConfig, cache: URL, credentialEnvironment: CredentialEnvironment,
              gateway: (any GatewayTranscribing)? = nil,
              makeGateway: (([String: String]) -> any GatewayTranscribing)? = nil, recorder: any VoiceAudioRecording = AudioRecorder(),
              permission: (@MainActor () async throws -> Void)? = nil) throws {
    guard let vendor = GatewayVendor(rawValue: config.voice.engine), GatewayTranscriptionModels.defaults[vendor] != nil else {
      throw SpeechInputError("This vendor does not support audio transcription.")
    }
    let name = config.agent.credential(for: config.voice.engine)
    let environment = try credentialEnvironment.merged(credentials: name.map { [config.voice.engine: $0] } ?? [:])
    self.config = config; self.cache = cache; self.recorder = recorder; self.permission = permission ?? { try await VoicePermissions.microphone() }
    self.gateway = gateway ?? makeGateway?(environment) ?? ProductionGatewayExecutor(environment: environment)
    let keyName = name ?? StriaConfig.AgentConfig.defaultCredentials[config.voice.engine]
    self.secrets = keyName.flatMap { environment[$0] }.map { [$0] } ?? []
  }

  public static func modelOptions(for engine: String) -> [String] {
    guard let vendor = GatewayVendor(rawValue: engine) else { return [] }
    return GatewayTranscriptionModels.defaults[vendor] ?? []
  }

  public static func parameters(config: StriaConfig, audioFile: URL) throws -> GatewayTranscriptionParams {
    guard let vendor = GatewayVendor(rawValue: config.voice.engine),
          let defaultModel = GatewayTranscriptionModels.defaults[vendor]?.first else {
      throw SpeechInputError("This vendor does not support audio transcription.")
    }
    let model = config.voice.model?.trimmingCharacters(in: .whitespacesAndNewlines)
    let language = config.voice.language == "auto" ? nil : config.voice.language.split(separator: "-").first.map { String($0).lowercased() }
    return GatewayTranscriptionParams(vendor: vendor, model: model.flatMap { $0.isEmpty ? nil : $0 } ?? defaultModel,
                                      audioFile: audioFile, mimeType: "audio/mp4", language: language,
                                      apiKeyEnvironment: config.agent.credential(for: config.voice.engine))
  }

  public func requestPermission() async throws { try await permission() }

  public func start(language: String, onEvent: @escaping @MainActor @Sendable (SpeechInputEvent) -> Void) async throws {
    _ = language
    file = try recorder.start(in: cache) { onEvent(.level($0)) }
  }

  public func stop() async throws -> String {
    defer { cancel() }
    do {
      try recorder.stop()
      guard let file else { throw SpeechInputError("No audio was recorded.") }
      return try await gateway.transcribe(Self.parameters(config: config, audioFile: file)).text
    } catch is CancellationError { throw CancellationError() } catch {
      throw SpeechInputError(SecretRedactor.redact(error.localizedDescription, secrets: secrets))
    }
  }

  public func cancel() {
    recorder.cancel()
    if let file { try? FileManager.default.removeItem(at: file) }
    file = nil
  }
}
