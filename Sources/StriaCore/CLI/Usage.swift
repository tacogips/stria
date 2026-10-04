import Foundation

public enum Usage {
  public static let general = """
  Usage: stria [--home <path>] <command> [args] [options]

  Commands:
    import <pdf> [--ocr | --no-ocr]
    ocr <docId> [--pages <list>] [--retry-failed]
    list
    show <docId>
    remove <docId>
    page image <docId> <page> [--output <path>]
    page text <docId> <page>
    page summary <docId> <page>
    summarize <docId> [--pages <list>] [--instruction <text>] [--language <name>]
    search <query> [--doc <docId>] [--limit <n>]
    ask <question> [--doc <docId>] [--page <n>] [--query <terms>] [--limit <n>] [--thread <id>] [--vendor <v> [--model <m>]]
    history [--doc <docId>] [--page <n>] [--limit <n>] [--threads]
    config get [<key>]
    config set <key> <value>
    paths

  Global options: --home <path>, --json, --help / -h, --version

  Output: every command prints one JSON object on stdout (keys sorted, paths absolute,
  dates ISO-8601 UTC). On failure stdout is empty and stderr gets
  {"error":{"code":"...","message":"..."}}. Exit codes: 0 ok, 1 io/database,
  2 usage or invalid PDF, 3 not found, 4 OCR/agent unavailable (config or credentials),
  5 OCR/agent call failed.

  Workflow for agents (RAG over imported PDFs):
    - Find pages: search "<phrase>" [--doc <docId>] -> results[].docId, page, snippet, imagePath
    - Read a page: page image <docId> <page> -> path of a PNG to view; page text -> OCR text;
      page summary -> the page's summary (summaries are not searched)
    - Answer and cite docId + page; show <docId> gives the outline for context
    - Or let stria answer: ask "<question>" [--doc <docId>] [--thread <id>] -> answer, citations
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
