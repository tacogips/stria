public struct ParsedInvocation: Equatable, Sendable {
  public let home: String?
  public let command: CLICommand

  public init(home: String?, command: CLICommand) {
    self.home = home
    self.command = command
  }
}

public enum CLICommand: Equatable, Sendable {
  case help(topic: String?)
  case version
  case importPDF(path: String, noOCR: Bool, forceOCR: Bool)
  case ocr(docId: String, pages: String?, retryFailed: Bool)
  case list
  case show(docId: String)
  case remove(docId: String)
  case pageImage(docId: String, page: Int, output: String?)
  case pageText(docId: String, page: Int)
  case search(query: String, docId: String?, limit: Int?)
  case ask(question: String, docId: String?, page: Int?, query: String?, limit: Int?, thread: String?, vendor: String?, model: String?)
  case history(docId: String?, page: Int?, limit: Int?, threads: Bool)
  case configGet(key: String?)
  case configSet(key: String, value: String)
  case paths
}
