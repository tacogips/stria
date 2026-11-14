import Foundation
public struct ContextPage: Equatable, Sendable {
  public var docId: String; public var title: String; public var page: Int; public var ocrText: String?; public var pngPath: URL
  public init(docId: String, title: String, page: Int, ocrText: String?, pngPath: URL) {
    self.docId = docId; self.title = title; self.page = page; self.ocrText = ocrText; self.pngPath = pngPath
  }
}
public struct ChatTurn: Equatable, Sendable {
  public var role: ChatRole; public var content: String
  public init(role: ChatRole, content: String) { self.role = role; self.content = content }
}
public struct AgentRequest: Equatable, Sendable {
  public var question: String; public var systemPrompt: String; public var contextPages: [ContextPage]
  public var history: [ChatTurn]; public var settings: ServiceSettings
  public init(question: String, systemPrompt: String, contextPages: [ContextPage], history: [ChatTurn], settings: ServiceSettings) {
    self.question = question; self.systemPrompt = systemPrompt; self.contextPages = contextPages; self.history = history; self.settings = settings
  }
}
public struct AgentAnswer: Equatable, Sendable {
  public var text: String
  public init(text: String) { self.text = text }
}
/// Receives answer text as it streams in. Chunks concatenate to the final answer.
public typealias AnswerChunkHandler = @Sendable (String) -> Void

public protocol AgentService: Sendable {
  /// Asks the model. `onChunk` is called with each streamed piece of the
  /// answer; services that cannot stream call it once with the whole text.
  func ask(_ request: AgentRequest, onChunk: @escaping AnswerChunkHandler) async throws -> AgentAnswer
}

public extension AgentService {
  func ask(_ request: AgentRequest) async throws -> AgentAnswer { try await ask(request) { _ in } }
}
