import Foundation

public enum Usage {
  public static let general = """
  Usage: stria [--home <path>] <command> [args] [options]

  Commands:
    import <pdf> [--no-ocr]
    ocr <docId> [--pages <list>] [--retry-failed]
    list
    show <docId>
    remove <docId>
    page image <docId> <page> [--output <path>]
    page text <docId> <page>
    search <query> [--doc <docId>] [--limit <n>]
    ask <question> [--doc <docId>] [--page <n>] [--query <terms>] [--limit <n>]
    history [--doc <docId>] [--page <n>] [--limit <n>]
    config get [<key>]
    config set <key> <value>
    paths

  Global options: --home <path>, --json, --help / -h, --version
  """

  public static func text(for topic: String?) -> String {
    guard let topic else { return general }
    let normalized = topic == "-h" || topic == "--help" ? nil : topic
    guard let normalized else { return general }
    let signatures = general.components(separatedBy: "\n").compactMap { line -> String? in
      let signature = line.trimmingCharacters(in: .whitespaces)
      return signature == normalized || signature.hasPrefix("\(normalized) ") ? signature : nil
    }
    guard !signatures.isEmpty else { return general }
    return "Usage: stria\n" + signatures.map { "  \($0)" }.joined(separator: "\n") + "\n"
  }
}
