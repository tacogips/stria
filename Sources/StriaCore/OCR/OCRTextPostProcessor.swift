import Foundation

public enum OCRTextPostProcessor {
  public static func clean(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```"), trimmed.contains("\n") else { return trimmed }
    var lines = trimmed.components(separatedBy: .newlines)
    guard lines.count >= 2 else { return trimmed }
    lines.removeFirst()
    lines.removeLast()
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
