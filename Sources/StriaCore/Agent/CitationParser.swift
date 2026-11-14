import Foundation

public struct CitationMarker: Equatable {
  public var docId: String
  public var page: Int
  public var range: Range<String.Index>

  public init(docId: String, page: Int, range: Range<String.Index>) {
    self.docId = docId
    self.page = page
    self.range = range
  }
}

public enum CitationParser {
  public static func markers(in text: String) -> [CitationMarker] {
    text.matches(of: /\[([0-9a-f]{16})\s+p\.\s*([0-9]+)\]/).compactMap { match in
      guard let page = Int(match.2) else { return nil }
      return CitationMarker(docId: String(match.1), page: page, range: match.range)
    }
  }
}
