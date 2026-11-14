import Foundation

struct TrigramTerms {
  let trigrams: [String]
  let shortTokens: [String]
}

enum SearchQueryBuilder {
  /// NFKC-normalizes and trims. Whitespace (including line breaks) between
  /// two CJK characters is removed: OCR keeps line breaks, Japanese has no
  /// inter-word spaces, and the trigram tokenizer would otherwise never match
  /// a term wrapped across a line. `search_text` and queries both use this,
  /// so they agree.
  static func normalize(_ text: String) -> String {
    let nfkc = text.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
    var result = String.UnicodeScalarView()
    var pendingWhitespace = String.UnicodeScalarView()
    var previousWasCJK = false
    for scalar in nfkc.unicodeScalars {
      if scalar.properties.isWhitespace {
        pendingWhitespace.append(scalar)
        continue
      }
      let isCJK = Self.isCJK(scalar)
      if !pendingWhitespace.isEmpty {
        if !(previousWasCJK && isCJK) { result.append(contentsOf: pendingWhitespace) }
        pendingWhitespace.removeAll()
      }
      result.append(scalar)
      previousWasCJK = isCJK
    }
    return String(result)
  }

  static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x3040...0x30FF,   // Hiragana, Katakana
         0x3400...0x4DBF,   // CJK Extension A
         0x4E00...0x9FFF,   // CJK Unified Ideographs
         0xF900...0xFAFF,   // CJK Compatibility Ideographs
         0xFF66...0xFF9F,   // Half-width Katakana
         0x3000...0x303F,   // CJK punctuation
         0x20000...0x2FA1F: // CJK Extensions B-F
      return true
    default:
      return false
    }
  }

  static func terms(_ text: String) -> [String] { normalize(text).split(whereSeparator: \.isWhitespace).map(String.init) }

  /// FTS when the backend has it and at least one term is long enough for a
  /// trigram; shorter terms are then applied as LIKE filters on the FTS body.
  static func mode(backend: SearchBackend, terms: [String]) -> MatchMode {
    backend == .fts5 && terms.contains { isTrigramTerm($0) } ? .fts : .like
  }

  static func isTrigramTerm(_ term: String) -> Bool { term.unicodeScalars.count >= 3 }

  static func ftsMatchExpression(terms: [String]) -> String {
    terms.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: " AND ")
  }

  static func likePattern(term: String) -> String {
    "%" + term.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "%", with: "\\%")
      .replacingOccurrences(of: "_", with: "\\_") + "%"
  }

  /// Common English question words add trigrams that match every page and
  /// drown the ranking. Japanese is not whitespace-tokenized, so this list is
  /// ASCII only.
  static let stopWords: Set<String> = [
    "the", "and", "for", "are", "but", "not", "you", "all", "any", "can", "had", "her", "was", "one", "our",
    "out", "has", "his", "how", "its", "may", "who", "did", "does", "this", "that", "what", "when", "where",
    "which", "while", "with", "from", "have", "into", "than", "then", "them", "they", "there", "these", "those",
    "about", "would", "could", "should", "will", "page", "pages", "document", "tell", "explain", "please",
    "summarize", "summary", "mean", "means", "mention", "mentions", "mentioned", "say", "says", "said"
  ]

  static func trigrams(question: String) -> TrigramTerms {
    let normalized = normalize(question)
    let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    let tokens = normalized.components(separatedBy: separators)
      .filter { !$0.isEmpty && !stopWords.contains($0.lowercased()) }
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
    guard !term.isEmpty, let match = text.range(of: term, options: [.caseInsensitive]) else { return String(text.prefix(80)) }
    let lower = text.index(match.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
    let upper = text.index(match.upperBound, offsetBy: 40, limitedBy: text.endIndex) ?? text.endIndex
    let prefix = String(text[lower..<match.lowerBound])
    let found = String(text[match])
    let suffix = String(text[match.upperBound..<upper])
    return (lower == text.startIndex ? "" : "...") + prefix + "[\(found)]" + suffix + (upper == text.endIndex ? "" : "...")
  }
}
