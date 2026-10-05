import Foundation

public struct GatewayAgentService: AgentService {
  private let paths: StriaPaths
  private let credentials: CredentialEnvironment
  let runner: GatewayPromptRunner

  public init(paths: StriaPaths, environment: [String: String], platform: StriaPlatform = .current,
              credentialStore: any CredentialStore = KeychainCredentialStore()) {
    self.init(paths: paths, environment: environment, runner: GatewayPromptRunner(), platform: platform, credentialStore: credentialStore)
  }

  init(paths: StriaPaths, environment: [String: String], runner: GatewayPromptRunner, platform: StriaPlatform = .current,
       credentialStore: any CredentialStore = KeychainCredentialStore()) {
    self.paths = paths
    credentials = CredentialEnvironment(environment: environment, platform: platform, store: credentialStore)
    self.runner = runner
  }

  public func ask(_ request: AgentRequest, onChunk: @escaping AnswerChunkHandler) async throws -> AgentAnswer {
    guard KnownVendors.isAvailableOnThisPlatform(request.settings.vendor, platform: credentials.platform) else {
      throw ServiceError.unavailable(KnownVendors.platformUnavailableReason)
    }
    let environment = try credentials.merged(settings: request.settings)
    let preflight = try GatewayPreflight.check(request.settings, environment: environment, platform: credentials.platform)
    let text = try await runner.run(
      settings: request.settings,
      systemPrompt: request.systemPrompt,
      parts: GatewayPromptParts.agentParts(request),
      cwd: paths.cache,
      environment: environment,
      secretValue: preflight.secretValue,
      onChunk: onChunk
    )
    return AgentAnswer(text: text)
  }
}
