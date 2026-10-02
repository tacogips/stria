import Foundation

public enum AskContext: Equatable, Sendable {
  case page(docId: String, page: Int)
  case nearby(docId: String, page: Int)
  case document(docId: String, anchorPage: Int?)
  case library
}

/// A vendor and model chosen for questions.
public struct AgentSelection: Equatable, Sendable {
  public static let vendorKey = "agent.lastVendor"
  public static let modelKey = "agent.lastModel"
  public var vendor: String
  public var model: String?
  public init(vendor: String, model: String?) { self.vendor = vendor; self.model = model }
}

public struct AskRequest: Sendable {
  public var question: String
  public var context: AskContext
  public var retrievalQuery: String?
  public var limit: Int?
  public var threadId: String?
  /// Receives the answer as it streams. Optional; the CLI leaves it nil.
  public var onChunk: AnswerChunkHandler?
  /// The vendor and model for this question; nil falls back to the last
  /// chat selection, then to `agent.vendor` / `agent.model` in config.
  public var selection: AgentSelection?

  public init(question: String, context: AskContext, retrievalQuery: String? = nil, limit: Int? = nil,
              threadId: String? = nil, selection: AgentSelection? = nil, onChunk: AnswerChunkHandler? = nil) {
    self.question = question
    self.context = context
    self.retrievalQuery = retrievalQuery
    self.limit = limit
    self.threadId = threadId
    self.selection = selection
    self.onChunk = onChunk
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
  /// Pages the answer actually cites with `[<docId> p.<page>]` markers, in
  /// order of first mention; all context pages when the answer cites none.
  public var citations: [Citation]
  /// Every page that was sent to the model.
  public var contextPages: [Citation]

  public init(threadId: String, answer: String, vendor: String, model: String?, runId: String,
              citations: [Citation], contextPages: [Citation]) {
    self.threadId = threadId
    self.answer = answer
    self.vendor = vendor
    self.model = model
    self.runId = runId
    self.citations = citations
    self.contextPages = contextPages
  }

  /// Picks the context pages cited in `answer`, falling back to all of them.
  public static func citedPages(in answer: String, contextPages: [Citation]) -> [Citation] {
    var seen = Set<PageRef>()
    let cited = CitationParser.markers(in: answer).compactMap { marker -> Citation? in
      let ref = PageRef(docId: marker.docId, page: marker.page)
      guard seen.insert(ref).inserted else { return nil }
      return contextPages.first { $0.docId == ref.docId && $0.page == ref.page }
    }
    return cited.isEmpty ? contextPages : cited
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
