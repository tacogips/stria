import Foundation

/// Writes the summary of one chat thread with the selected agent vendor and
/// model, from the first question through the newest message.
struct ThreadSummarizer: Sendable {
  let environment: StriaEnvironment
  let store: StriaStore

  /// Characters of conversation sent to the model; the first exchange is
  /// always kept, and the middle is elided when a thread is longer.
  static let maxTranscriptCharacters = 24_000

  func summarize(threadId: String, selection: AgentSelection?) async throws -> String {
    let messages = try await store.threadMessages(threadId: threadId)
    guard let last = messages.last else { throw StriaError.usage("Chat thread not found: \(threadId)") }
    let resolved = try await AskCoordinator(environment: environment, store: store).resolveSelection(selection)
    let request = AgentRequest(
      question: Self.transcript(messages),
      systemPrompt: AgentDefaults.summaryPrompt,
      contextPages: [],
      history: [],
      settings: ServiceSettings(agent: environment.config.agent, vendor: resolved.vendor, model: resolved.model)
    )
    let answer: AgentAnswer
    do {
      answer = try await environment.agentService.ask(request)
    } catch let error as ServiceError {
      switch error {
      case .unavailable(let reason): throw StriaError.serviceUnavailable(SecretRedactor.truncate(reason))
      case .failed(let reason): throw StriaError.serviceFailed(SecretRedactor.truncate(reason))
      }
    }
    let summary = OCRTextPostProcessor.clean(answer.text)
    guard !summary.isEmpty else { throw StriaError.serviceFailed("The summary came back empty") }
    try await store.setThreadSummary(threadId: threadId, summary: summary, throughMessageId: last.id)
    return summary
  }

  /// "User: ... / Assistant: ..." lines, oldest first, failed answers left
  /// out, the first exchange kept and the middle elided past the limit.
  static func transcript(_ messages: [ChatMessageRecord], limit: Int = maxTranscriptCharacters) -> String {
    let lines = messages.filter { $0.status == .ok }.map { message in
      "\(message.role == .user ? "User" : "Assistant"): \(message.content)"
    }
    let header = "Conversation to summarize:\n\n"
    let full = lines.joined(separator: "\n\n")
    guard full.count > limit, lines.count > 2 else { return header + String(full.prefix(limit)) }
    let head = lines.prefix(2).joined(separator: "\n\n")
    let budget = max(0, limit - head.count)
    var tail: [String] = []
    var used = 0
    for line in lines.dropFirst(2).reversed() {
      guard used + line.count <= budget else { break }
      tail.insert(line, at: 0)
      used += line.count + 2
    }
    return header + head + "\n\n[... earlier turns omitted ...]\n\n" + tail.joined(separator: "\n\n")
  }
}
