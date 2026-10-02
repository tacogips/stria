import ACP
import AgentGateway
import AgentGatewayAppCore
import Foundation

struct GatewayPromptRunner {
  func run(
    settings: ServiceSettings,
    systemPrompt: String?,
    parts: [PromptPart],
    cwd: URL,
    environment: [String: String],
    secretValue: String?,
    onChunk: AnswerChunkHandler? = nil
  ) async throws(ServiceError) -> String {
    guard let vendor = GatewayVendor(rawValue: settings.vendor) else {
      throw .unavailable("unknown vendor \(settings.vendor)")
    }
    let defaults = GatewayAgentDefaults(
      vendor: vendor,
      model: settings.model,
      systemPrompt: systemPrompt,
      apiKeyEnvironment: settings.apiKeyEnvironment
    )
    let agent = GatewayACPAgent(defaults: defaults, executor: ProductionGatewayExecutor(environment: environment))
    let (client, _) = await ACPClientConnection.inProcess(agent: agent)
    do {
      _ = try await client.initialize()
      let session = try await client.newSession(ACPNewSessionRequest(cwd: cwd.path))
      var content = [ACPContentBlock]()
      for part in GatewayPromptParts.rendered(parts, for: vendor) {
        switch part {
        case let .text(text):
          content.append(.text(text))
        case let .image(url):
          content.append(contentsOf: try gatewayImageContentBlocks([.filePath(url.path)]))
        }
      }
      let request = ACPPromptRequest(sessionId: session.sessionId, prompt: content)
      var messageText = ""
      var stopReason: ACPStopReason?
      for try await event in client.promptStream(request) {
        switch event {
        case .update(.agentMessageChunk(.text(let chunk))):
          messageText += chunk.text
          onChunk?(chunk.text)
        case .update:
          break
        case .response(let response):
          stopReason = response.stopReason
        }
      }
      guard let stopReason else { throw ServiceError.failed("prompt stream ended without a response") }
      guard stopReason == .endTurn else { throw ServiceError.failed("stop reason: \(stopReason.rawValue)") }
      return messageText
    } catch let error as ServiceError {
      throw error
    } catch {
      throw .failed(SecretRedactor.redact(String(describing: error), secrets: [secretValue].compactMap { $0 }))
    }
  }
}
