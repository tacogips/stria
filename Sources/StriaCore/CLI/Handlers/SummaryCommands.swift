import Foundation

enum SummaryCommands {
  static func run(_ command: CLICommand, library: StriaLibrary) async throws -> any Encodable {
    switch command {
    case .pageSummary(let docId, let page):
      let record = try await library.document(id: docId)
      guard page <= record.pageCount else { throw StriaError.pageNotFound("Page \(page) not found in document \(docId)") }
      return PageSummaryOutput(docId: docId, page: page, record: try await library.pageSummary(documentId: docId, page: page))
    case .summarize(let docId, let pages, let instruction, let language):
      let selection: PageSummarySelection
      if let pages {
        let record = try await library.document(id: docId)
        selection = .pages(try PageListParser.parse(pages, pageCount: record.pageCount))
      } else {
        selection = .missing
      }
      if let language, language.trimmingCharacters(in: .whitespaces).isEmpty { throw StriaError.usage("--language must not be empty") }
      let result = try await library.summarizePages(
        documentId: docId, request: PageSummaryRequest(selection: selection, instruction: instruction, language: language))
      if let reason = result.unavailableReason { throw StriaError.serviceUnavailable(reason) }
      return SummarizeOutput(docId: docId, summarized: result.summarized, skipped: result.skipped, failures: result.failures)
    default:
      throw StriaError.usage("Not a summary command")
    }
  }
}

/// `stria page summary`: the stored summary, with explicit nulls.
public struct PageSummaryOutput: Encodable {
  public let docId: String
  public let page: Int
  public let record: PageSummaryRecord?

  enum CodingKeys: String, CodingKey { case docId, page, status, summary, error, language, instruction, vendor, model, stale, updatedAt }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(docId, forKey: .docId)
    try container.encode(page, forKey: .page)
    try container.encode(record?.status.rawValue ?? "none", forKey: .status)
    try container.encode(record?.summary, forKey: .summary)
    try container.encode(record?.error, forKey: .error)
    try container.encode(record?.language, forKey: .language)
    try container.encode(record?.instruction, forKey: .instruction)
    try container.encode(record?.vendor, forKey: .vendor)
    try container.encode(record?.model, forKey: .model)
    try container.encode(record?.isStale ?? false, forKey: .stale)
    try container.encode(record?.updatedAt, forKey: .updatedAt)
  }
}

/// `stria summarize`: which pages were summarized, skipped (not OCRed) or failed.
public struct SummarizeOutput: Encodable {
  public let docId: String
  public let summarized: [Int]
  public let skipped: [Int]
  public let failures: [OCRFailure]
}
