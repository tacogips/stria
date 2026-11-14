public struct SearchHit: Codable, Equatable, Sendable {
  public var docId: String; public var title: String; public var page: Int; public var snippet: String; public var score: Double
  public init(docId: String, title: String, page: Int, snippet: String, score: Double) {
    self.docId = docId; self.title = title; self.page = page; self.snippet = snippet; self.score = score
  }
}
public struct SearchOutcome: Codable, Equatable, Sendable {
  public var matchMode: MatchMode; public var hits: [SearchHit]
  public init(matchMode: MatchMode, hits: [SearchHit]) { self.matchMode = matchMode; self.hits = hits }
}
