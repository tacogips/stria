import ACP
import AgentGateway
import AgentGatewayAppCore
import Foundation

/// Runs one prompt turn against agent-gateway in-process. Each call owns its
/// agent, connection and session, and closes them on every exit path.
struct GatewayPromptRunner: Sendable {
  /// Builds the executor for a call. Injectable so offline tests can drive
  /// the full ACP path with a fake gateway.
  var makeExecutor: @Sendable ([String: String]) -> any GatewayExecuting = { ProductionGatewayExecutor(environment: $0) }

  func run(
    settings: ServiceSettings,
    systemPrompt: String?,
    parts: [PromptPart],
    cwd: URL,
    environment: [String: String],
    secretValue: String?,
    onChunk: AnswerChunkHandler? = nil
  ) async throws -> String {
    guard let vendor = GatewayVendor(rawValue: settings.vendor) else {
      throw ServiceError.unavailable("unknown vendor \(settings.vendor)")
    }
    let defaults = GatewayAgentDefaults(
      vendor: vendor,
      model: settings.model,
      systemPrompt: systemPrompt,
      apiKeyEnvironment: settings.apiKeyEnvironment
    )
    let agent = GatewayACPAgent(defaults: defaults, executor: makeExecutor(environment))
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
      let text = try await prompt(client: client, request: request, timeoutSeconds: settings.timeoutSeconds, onChunk: onChunk)
      await client.stop()
      return text
    } catch let error as ServiceError {
      await client.stop()
      throw error
    } catch is CancellationError {
      await client.stop()
      throw CancellationError()
    } catch {
      await client.stop()
      throw ServiceError.failed(SecretRedactor.redact(String(describing: error), secrets: [secretValue].compactMap { $0 }))
    }
  }

  /// Races the prompt turn against the deadline. On timeout or cancellation
  /// the vendor turn is cancelled through ACP so a CLI agent process does not
  /// keep running after stria has given up on it.
  private func prompt(
    client: ACPClientConnection, request: ACPPromptRequest, timeoutSeconds: Int, onChunk: AnswerChunkHandler?
  ) async throws -> String {
    try await withThrowingTaskGroup(of: String.self) { group in
      group.addTask { try await consume(client: client, request: request, onChunk: onChunk) }
      group.addTask {
        try await Task.sleep(for: .seconds(max(1, timeoutSeconds)))
        throw ServiceError.failed("timed out after \(timeoutSeconds) s")
      }
      do {
        guard let text = try await group.next() else { throw ServiceError.failed("prompt produced no result") }
        group.cancelAll()
        return text
      } catch {
        group.cancelAll()
        try? await client.cancel(sessionId: request.sessionId)
        if Task.isCancelled { throw CancellationError() }
        throw error
      }
    }
  }

  private func consume(client: ACPClientConnection, request: ACPPromptRequest, onChunk: AnswerChunkHandler?) async throws -> String {
    var messageText = ""
    var stopReason: ACPStopReason?
    var resultText: String?
    for try await event in client.promptStream(request) {
      switch event {
      case .update(.agentMessageChunk(.text(let chunk))):
        messageText += chunk.text
        onChunk?(chunk.text)
      case .update:
        break
      case .response(let response):
        stopReason = response.stopReason
        // The gateway's authoritative final text; streamed chunks are the same
        // text for every vendor that streams, and the only text for those that do not.
        resultText = response.meta?["agentGateway"]?.objectValue?["resultText"]?.stringValue
      }
    }
    try Task.checkCancellation()
    guard let stopReason else { throw ServiceError.failed("prompt stream ended without a response") }
    guard stopReason == .endTurn else { throw ServiceError.failed("stop reason: \(stopReason.rawValue)") }
    if let resultText, !resultText.isEmpty { return resultText }
    return messageText
  }
}
