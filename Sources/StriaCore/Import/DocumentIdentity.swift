import CryptoKit
import Foundation

public enum DocumentIdentity {
  public static func sha256Hex(of url: URL) throws -> String {
    do {
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      var hasher = SHA256()
      while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
        hasher.update(data: data)
      }
      return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    } catch {
      throw StriaError.io("Could not hash file at \(url.path): \(error.localizedDescription)")
    }
  }

  public static func docId(sha256Hex: String) -> String {
    String(sha256Hex.prefix(16))
  }
}
