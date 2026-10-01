import Foundation

public enum SecretRedactor {
  public static func redact(_ text: String, secrets: [String]) -> String {
    let redacted = secrets.filter { !$0.isEmpty }.reduce(text) { result, secret in
      result.replacingOccurrences(of: secret, with: "[REDACTED]")
    }
    return truncate(redacted)
  }

  public static func truncate(_ text: String, limit: Int = 2000) -> String {
    guard limit >= 0, text.count > limit else { return text }
    return String(text.prefix(limit))
  }
}
