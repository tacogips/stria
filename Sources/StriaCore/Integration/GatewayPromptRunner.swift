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
    secretValue: String?
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
      let result = try await client.promptCollecting(ACPPromptRequest(sessionId: session.sessionId, prompt: content))
      guard result.response.stopReason == .endTurn else {
        throw ServiceError.failed("stop reason: \(result.response.stopReason.rawValue)")
      }
      return result.messageText
    } catch let error as ServiceError {
      throw error
    } catch {
      throw .failed(SecretRedactor.redact(String(describing: error), secrets: [secretValue].compactMap { $0 }))
    }
  }
}
