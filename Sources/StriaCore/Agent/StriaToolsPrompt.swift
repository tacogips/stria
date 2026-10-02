import Foundation

/// The "Stria tools" section appended to the system prompt for vendors that
/// can run commands (the CLI vendors): how to search the library and read
/// pages with the `stria` command, pointed at this data root. Read-only
/// commands only; import, remove and config are never mentioned.
public enum StriaToolsPrompt {
  public static func section(executable: URL, dataRoot: URL, currentDocumentId: String?) -> String {
    let stria = "\(shellQuoted(executable.path)) --home \(shellQuoted(dataRoot.path))"
    let current = currentDocumentId.map { "The document the user is reading has docId \($0)." } ?? "No document is open; the question is about the whole library."
    return """
      Stria tools
      You may run the stria command (read-only) to look beyond the supplied pages. Every command prints one JSON object.
      \(current)
      - Search this document: \(stria) search "<phrase>" --doc <docId> --limit 10
      - Search every document in the library: \(stria) search "<phrase>" --limit 10
        Results list docId, title, page, snippet and imagePath. Prefer distinctive phrases of 3 or more characters; \
      a two-character Japanese word is matched literally.
      - Read a page: \(stria) page image <docId> <page> (prints the PNG path to open) and \(stria) page text <docId> <page> (OCR text)
      - Document outline and metadata: \(stria) show <docId>; all documents: \(stria) list
      Use at most a few searches, then answer. Cite pages found this way exactly like the supplied ones: [<docId> p.<page>].
      """
  }

  /// Finds the `stria` executable: next to the running executable (a
  /// SwiftPM build or a Homebrew install), then the usual install paths,
  /// then PATH. nil when none exists, in which case no tools section is sent.
  public static func locateExecutable(environment: [String: String] = ProcessInfo.processInfo.environment,
                                      fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> URL? {
    var candidates: [String] = []
    if let own = Bundle.main.executableURL {
      candidates.append(own.deletingLastPathComponent().appendingPathComponent("stria").path)
    }
    candidates += ["/opt/homebrew/bin/stria", "/usr/local/bin/stria"]
    for directory in (environment["PATH"] ?? "").split(separator: ":") {
      candidates.append("\(directory)/stria")
    }
    return candidates.first(where: fileExists).map { URL(fileURLWithPath: $0) }
  }

  static func shellQuoted(_ value: String) -> String {
    value.contains(where: { $0 == " " || $0 == "\"" || $0 == "'" || $0 == "$" }) ? "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" : value
  }
}
