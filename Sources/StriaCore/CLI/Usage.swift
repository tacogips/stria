import Foundation

public enum Usage {
  public static let general = """
  Usage: stria [--home <path>] <command> [args] [options]

  Commands:
    import <pdf> [--no-ocr]
    ocr <docId> [--pages <list>] [--retry-failed]
    list
    show <docId>
    page image <docId> <page> [--output <path>]
    page text <docId> <page>
    search <query> [--doc <docId>] [--limit <n>]
    ask <question> [--doc <docId>] [--page <n>] [--query <terms>] [--limit <n>]
    history [--doc <docId>] [--page <n>] [--limit <n>]
    config get [<key>]
    config set <key> <value>
    paths

  Global options: --home <path>, --json, --help, --version
  """

  public static func text(for topic: String?) -> String {
    guard let topic else { return general }
    let normalized = topic == "-h" || topic == "--help" ? nil : topic
    guard let normalized else { return general }
    let signature = general.components(separatedBy: "\n").first { $0.trimmingCharacters(in: .whitespaces).hasPrefix("\(normalized) ") || $0.trimmingCharacters(in: .whitespaces) == normalized }
    return signature.map { "Usage: stria \($0.trimmingCharacters(in: .whitespaces))\n" } ?? general
  }
}
