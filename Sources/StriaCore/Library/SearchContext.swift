import Foundation

/// A run of text in a search result's context; hits are the matched terms.
public struct TextSegment: Equatable, Sendable {
  public let text: String
  public let isHit: Bool
  public init(text: String, isHit: Bool) { self.text = text; self.isHit = isHit }
}

/// Builds "text around the hit" for search results, from the page's OCR text
/// normalized the same way as the index (NFKC, CJK line breaks joined), so a
/// term wrapped across a line is found here too.
public enum SearchContextBuilder {
  /// Up to `radius` characters before the first hit and after the last hit
  /// in the window; every occurrence of every term inside it is a hit.
  public static func segments(text: String, query: String, radius: Int = 60) -> [TextSegment] {
    let normalized = SearchQueryBuilder.normalize(text).replacingOccurrences(of: "\n", with: " ")
    let terms = SearchQueryBuilder.terms(query).filter { !$0.isEmpty }
    guard !terms.isEmpty,
          let first = terms.compactMap({ normalized.range(of: $0, options: .caseInsensitive) })
            .min(by: { $0.lowerBound < $1.lowerBound }) else {
      return []
    }
    let start = normalized.index(first.lowerBound, offsetBy: -radius, limitedBy: normalized.startIndex) ?? normalized.startIndex
    let end = normalized.index(first.upperBound, offsetBy: radius * 2, limitedBy: normalized.endIndex) ?? normalized.endIndex
    let window = String(normalized[start..<end])

    var hits: [Range<String.Index>] = []
    for term in terms {
      var searchFrom = window.startIndex
      while let range = window.range(of: term, options: .caseInsensitive, range: searchFrom..<window.endIndex) {
        hits.append(range)
        searchFrom = range.upperBound
      }
    }
    hits.sort { $0.lowerBound < $1.lowerBound }

    var segments: [TextSegment] = []
    if start > normalized.startIndex { segments.append(TextSegment(text: "…", isHit: false)) }
    var cursor = window.startIndex
    for hit in hits where hit.lowerBound >= cursor {
      if cursor < hit.lowerBound { segments.append(TextSegment(text: String(window[cursor..<hit.lowerBound]), isHit: false)) }
      segments.append(TextSegment(text: String(window[hit]), isHit: true))
      cursor = hit.upperBound
    }
    if cursor < window.endIndex { segments.append(TextSegment(text: String(window[cursor...]), isHit: false)) }
    if end < normalized.endIndex { segments.append(TextSegment(text: "…", isHit: false)) }
    return segments
  }

  /// Fallback for a hit whose OCR text did not contain a term literally
  /// (should not happen): the index snippet, whose matches are in [brackets].
  public static func segments(fromBracketedSnippet snippet: String) -> [TextSegment] {
    var segments: [TextSegment] = []
    var rest = Substring(snippet)
    while let open = rest.firstIndex(of: "["), let close = rest[open...].firstIndex(of: "]") {
      if rest.startIndex < open { segments.append(TextSegment(text: String(rest[rest.startIndex..<open]), isHit: false)) }
      segments.append(TextSegment(text: String(rest[rest.index(after: open)..<close]), isHit: true))
      rest = rest[rest.index(after: close)...]
    }
    if !rest.isEmpty { segments.append(TextSegment(text: String(rest), isHit: false)) }
    return segments
  }
}
