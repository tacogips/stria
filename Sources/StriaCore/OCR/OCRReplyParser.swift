import Foundation

/// The OCR reply a model must send: `{"body": "...", "tags": ["...", ...]}`.
public struct ParsedOCRReply: Equatable, Sendable {
  public var body: String
  public var tags: [String]
  public init(body: String, tags: [String]) { self.body = body; self.tags = tags }
}

public enum OCRReplyParser {
  public static let maxTags = 40
  public static let maxTagLength = 80

  /// Parses a JSON OCR reply. Code fences or text around the object are
  /// tolerated; a missing or mistyped `body` or `tags` is a format error
  /// (the message says what is wrong, for the retry log and the page error).
  public static func parse(_ reply: String) throws(StriaError) -> ParsedOCRReply {
    guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end else {
      throw .serviceFailed("OCR reply is not a JSON object")
    }
    let json = Data(reply[start...end].utf8)
    guard let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else {
      throw .serviceFailed("OCR reply is not valid JSON")
    }
    guard let body = object["body"] as? String else { throw .serviceFailed("OCR reply JSON has no string \"body\"") }
    guard let rawTags = object["tags"] as? [Any], let tags = rawTags as? [String] else {
      throw .serviceFailed("OCR reply JSON has no \"tags\" array of strings")
    }
    var cleanedBody = OCRTextPostProcessor.clean(body)
    if cleanedBody == OCRDefaults.noTextSentinel { cleanedBody = "" }
    return ParsedOCRReply(body: cleanedBody, tags: normalizedTags(tags))
  }

  /// Trimmed, non-empty, de-duplicated (ignoring case and width), capped tags
  /// in the order the model gave them.
  public static func normalizedTags(_ tags: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for tag in tags {
      let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "#")))
      guard !trimmed.isEmpty else { continue }
      let capped = String(trimmed.prefix(maxTagLength))
      let key = capped.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
      guard seen.insert(key).inserted else { continue }
      result.append(capped)
      if result.count == maxTags { break }
    }
    return result
  }
}
