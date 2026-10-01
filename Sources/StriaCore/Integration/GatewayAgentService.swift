import Foundation

public struct GatewayAgentService: AgentService {
  private let paths: StriaPaths
  private let environment: [String: String]

  public init(paths: StriaPaths, environment: [String: String]) {
    self.paths = paths
    self.environment = environment
  }

  public func ask(_ request: AgentRequest) async throws -> AgentAnswer {
    let preflight = try GatewayPreflight.check(request.settings, environment: environment)
    let text = try await GatewayPromptRunner().run(
      settings: request.settings,
      systemPrompt: request.systemPrompt,
      parts: GatewayPromptParts.agentParts(request),
      cwd: paths.cache,
      environment: environment,
      secretValue: preflight.secretValue
    )
    return AgentAnswer(text: text)
  }
}
