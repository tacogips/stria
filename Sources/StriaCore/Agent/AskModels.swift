import Foundation

public enum AskContext: Equatable, Sendable {
  case page(docId: String, page: Int)
  case nearby(docId: String, page: Int)
  case document(docId: String, anchorPage: Int?)
  case library
}

public struct AskRequest: Sendable {
  public var question: String
  public var context: AskContext
  public var retrievalQuery: String?
  public var limit: Int?
  public var threadId: String?

  public init(question: String, context: AskContext, retrievalQuery: String? = nil, limit: Int? = nil, threadId: String? = nil) {
    self.question = question
    self.context = context
    self.retrievalQuery = retrievalQuery
    self.limit = limit
    self.threadId = threadId
  }
}

public struct Citation: Codable, Equatable, Sendable {
  public var docId: String
  public var title: String
  public var page: Int
  public var imagePath: String

  public init(docId: String, title: String, page: Int, imagePath: String) {
    self.docId = docId
    self.title = title
    self.page = page
    self.imagePath = imagePath
  }
}

public struct AskResponse: Sendable, Equatable {
  public var threadId: String
  public var answer: String
  public var vendor: String
  public var model: String?
  public var runId: String
  public var citations: [Citation]

  public init(threadId: String, answer: String, vendor: String, model: String?, runId: String, citations: [Citation]) {
    self.threadId = threadId
    self.answer = answer
    self.vendor = vendor
    self.model = model
    self.runId = runId
    self.citations = citations
  }
}

public struct SearchResultItem: Sendable, Equatable {
  public var docId: String
  public var title: String
  public var page: Int
  public var snippet: String
  public var score: Double
  public var imagePath: String
  public var imageCached: Bool

  public init(docId: String, title: String, page: Int, snippet: String, score: Double, imagePath: String, imageCached: Bool) {
    self.docId = docId
    self.title = title
    self.page = page
    self.snippet = snippet
    self.score = score
    self.imagePath = imagePath
    self.imageCached = imageCached
  }
}

public struct SearchResponse: Sendable, Equatable {
  public var query: String
  public var matchMode: MatchMode
  public var results: [SearchResultItem]

  public init(query: String, matchMode: MatchMode, results: [SearchResultItem]) {
    self.query = query
    self.matchMode = matchMode
    self.results = results
  }
}
