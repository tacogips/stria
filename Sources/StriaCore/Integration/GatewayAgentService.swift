import Foundation

public struct GatewayAgentService: AgentService {
  private let paths: StriaPaths
  private let environment: [String: String]
  let runner: GatewayPromptRunner

  public init(paths: StriaPaths, environment: [String: String]) {
    self.init(paths: paths, environment: environment, runner: GatewayPromptRunner())
  }

  init(paths: StriaPaths, environment: [String: String], runner: GatewayPromptRunner) {
    self.paths = paths
    self.environment = environment
    self.runner = runner
  }

  public func ask(_ request: AgentRequest, onChunk: @escaping AnswerChunkHandler) async throws -> AgentAnswer {
    let preflight = try GatewayPreflight.check(request.settings, environment: environment)
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
