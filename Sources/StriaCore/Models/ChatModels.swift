import Foundation
public struct ChatMessageRecord: Codable, Equatable, Sendable {
  public var id: Int64; public var threadId: String; public var role: ChatRole; public var status: MessageStatus; public var content: String
  public var documentId: String?; public var pageNumber: Int?; public var vendor: String?; public var model: String?
  public var agentRunId: String?; public var citations: [PageRef]; public var createdAt: Date
  public init(id: Int64, threadId: String, role: ChatRole, status: MessageStatus, content: String, documentId: String? = nil,
              pageNumber: Int? = nil, vendor: String? = nil, model: String? = nil, agentRunId: String? = nil,
              citations: [PageRef] = [], createdAt: Date) {
    self.id = id; self.threadId = threadId; self.role = role; self.status = status; self.content = content
    self.documentId = documentId; self.pageNumber = pageNumber; self.vendor = vendor; self.model = model
    self.agentRunId = agentRunId; self.citations = citations; self.createdAt = createdAt
  }
}
public struct NewChatThread: Codable, Equatable, Sendable {
  public var documentId: String?; public var pageNumber: Int?; public var scope: ChatScope
  public init(documentId: String?, pageNumber: Int?, scope: ChatScope) { self.documentId = documentId; self.pageNumber = pageNumber; self.scope = scope }
}
public struct AskExchange: Codable, Equatable, Sendable {
  public var threadId: String; public var newThread: NewChatThread?; public var question: String; public var anchorDocumentId: String?
  public var anchorPage: Int?; public var assistantStatus: MessageStatus; public var assistantContent: String; public var vendor: String
  public var model: String?; public var citations: [PageRef]; public var run: AgentRunRecord; public var createdAt: Date
  public init(threadId: String, newThread: NewChatThread?, question: String, anchorDocumentId: String?, anchorPage: Int?,
              assistantStatus: MessageStatus, assistantContent: String, vendor: String, model: String?, citations: [PageRef],
              run: AgentRunRecord, createdAt: Date) {
    self.threadId = threadId; self.newThread = newThread; self.question = question; self.anchorDocumentId = anchorDocumentId
    self.anchorPage = anchorPage; self.assistantStatus = assistantStatus; self.assistantContent = assistantContent
    self.vendor = vendor; self.model = model; self.citations = citations; self.run = run; self.createdAt = createdAt
  }
}
