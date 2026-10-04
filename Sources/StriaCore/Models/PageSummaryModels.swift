import Foundation

public enum PageSummaryStatus: String, Codable, Sendable { case done, failed }

/// A page's stored summary. It is kept apart from the OCR text and is never
/// part of search.
public struct PageSummaryRecord: Equatable, Sendable {
  public var documentId: String
  public var pageNumber: Int
  public var status: PageSummaryStatus
  /// The summary; "" for a page without text. nil when the call failed.
  public var summary: String?
  public var error: String?
  public var language: String
  /// Extra instructions given for this summary (a redo from the app).
  public var instruction: String?
  public var vendor: String
  public var model: String?
  /// True when the page was OCRed again after this summary was written.
  public var isStale: Bool
  public var updatedAt: Date

  public init(documentId: String, pageNumber: Int, status: PageSummaryStatus, summary: String?, error: String?,
              language: String, instruction: String?, vendor: String, model: String?, isStale: Bool = false, updatedAt: Date) {
    self.documentId = documentId; self.pageNumber = pageNumber; self.status = status; self.summary = summary
    self.error = error; self.language = language; self.instruction = instruction; self.vendor = vendor
    self.model = model; self.isStale = isStale; self.updatedAt = updatedAt
  }
}

/// Which pages a summary run covers.
public enum PageSummarySelection: Equatable, Sendable {
  /// OCRed pages without a current summary (none, failed or stale).
  case missing
  case pages([Int])
}

/// Options of one summary run.
public struct PageSummaryRequest: Equatable, Sendable {
  public var selection: PageSummarySelection
  /// Extra instructions appended to the page text (nil or blank for none).
  public var instruction: String?
  /// Overrides `summary.language` for this run.
  public var language: String?

  public init(selection: PageSummarySelection, instruction: String? = nil, language: String? = nil) {
    self.selection = selection; self.instruction = instruction; self.language = language
  }
}

public struct PageSummaryProgress: Equatable, Sendable {
  public var completed: Int
  public var total: Int
  /// The page being summarized now; nil once the run ends.
  public var currentPage: Int?

  public init(completed: Int, total: Int, currentPage: Int?) {
    self.completed = completed; self.total = total; self.currentPage = currentPage
  }
}

public struct PageSummaryRunResult: Equatable, Sendable {
  public var docId: String
  public var summarized: [Int]
  public var failures: [OCRFailure]
  /// Pages left out because they have no OCR text yet.
  public var skipped: [Int]
  /// Set when no summary could be attempted (no vendor, missing key).
  public var unavailableReason: String?

  public init(docId: String, summarized: [Int], failures: [OCRFailure], skipped: [Int], unavailableReason: String?) {
    self.docId = docId; self.summarized = summarized; self.failures = failures
    self.skipped = skipped; self.unavailableReason = unavailableReason
  }
}
