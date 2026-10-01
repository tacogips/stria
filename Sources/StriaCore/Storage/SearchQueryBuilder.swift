import Foundation

struct TrigramTerms {
  let trigrams: [String]
  let shortTokens: [String]
}

enum SearchQueryBuilder {
  static func normalize(_ text: String) -> String {
    text.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func terms(_ text: String) -> [String] { normalize(text).split(whereSeparator: \.isWhitespace).map(String.init) }

  static func mode(backend: SearchBackend, terms: [String]) -> MatchMode {
    backend == .fts5 && terms.allSatisfy { $0.unicodeScalars.count >= 3 } ? .fts : .like
  }

  static func ftsMatchExpression(terms: [String]) -> String {
    terms.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: " AND ")
  }

  static func likePattern(term: String) -> String {
    "%" + term.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "%", with: "\\%")
      .replacingOccurrences(of: "_", with: "\\_") + "%"
  }

  static func trigrams(question: String) -> TrigramTerms {
    let normalized = normalize(question)
    let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    let tokens = normalized.components(separatedBy: separators).filter { !$0.isEmpty }
    var seen = Set<String>()
    var grams: [String] = []
    var short: [String] = []
    for token in tokens {
      let scalars = Array(token.unicodeScalars)
      guard scalars.count >= 3 else { short.append(token); continue }
      for start in 0...(scalars.count - 3) {
        let gram = String(String.UnicodeScalarView(scalars[start..<(start + 3)]))
        if seen.insert(gram).inserted {
          grams.append(gram)
          if grams.count == 64 { return TrigramTerms(trigrams: grams, shortTokens: short) }
        }
      }
    }
    return TrigramTerms(trigrams: grams, shortTokens: short)
  }

  static func swiftSnippet(text: String, term: String) -> String {
    guard !term.isEmpty, let match = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) else { return String(text.prefix(80)) }
    let lower = text.index(match.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
    let upper = text.index(match.upperBound, offsetBy: 40, limitedBy: text.endIndex) ?? text.endIndex
    let prefix = String(text[lower..<match.lowerBound])
    let found = String(text[match])
    let suffix = String(text[match.upperBound..<upper])
    return (lower == text.startIndex ? "" : "...") + prefix + "[\(found)]" + suffix + (upper == text.endIndex ? "" : "...")
  }
}
