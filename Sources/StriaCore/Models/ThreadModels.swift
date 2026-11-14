import Foundation

/// One conversation as the history list shows it: its summary (when one has
/// been generated) and the question that started it.
public struct ThreadOverview: Identifiable, Equatable, Sendable {
  public var id: String { threadId }
  public let threadId: String
  /// The page the conversation started on (nil for a library-wide ask).
  public let documentId: String?
  public let pageNumber: Int?
  /// The AI-written title; nil until one is generated.
  public let title: String?
  public let firstQuestion: String
  public let summary: String?
  /// False when messages were added after the summary was written.
  public let isSummaryCurrent: Bool
  public let messageCount: Int
  public let lastMessageId: Int64
  public let updatedAt: Date

  public init(threadId: String, documentId: String?, pageNumber: Int?, title: String? = nil, firstQuestion: String, summary: String?,
              isSummaryCurrent: Bool, messageCount: Int, lastMessageId: Int64, updatedAt: Date) {
    self.threadId = threadId
    self.documentId = documentId
    self.pageNumber = pageNumber
    self.title = title
    self.firstQuestion = firstQuestion
    self.summary = summary
    self.isSummaryCurrent = isSummaryCurrent
    self.messageCount = messageCount
    self.lastMessageId = lastMessageId
    self.updatedAt = updatedAt
  }

  /// The title, or the first question's first line until a title exists.
  public var displayTitle: String { title ?? Self.fallbackTitle(firstQuestion) }

  public static func fallbackTitle(_ question: String, limit: Int = 60) -> String {
    let line = question.split(whereSeparator: \.isNewline).first.map(String.init) ?? question
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.count > limit ? String(trimmed.prefix(limit - 1)) + "\u{2026}" : trimmed
  }
}
