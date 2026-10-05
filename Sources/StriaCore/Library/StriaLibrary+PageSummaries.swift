import Foundation

public extension StriaLibrary {
  /// Summarizes the chosen pages in page order (see `PageSummaryCoordinator`).
  func summarizePages(documentId: String, request: PageSummaryRequest,
                      onProgress: @escaping @Sendable (PageSummaryProgress) -> Void = { _ in }) async throws -> PageSummaryRunResult {
    try await PageSummaryCoordinator(library: self).run(documentId: documentId, request: request, onProgress: onProgress)
  }

  func pageSummary(documentId: String, page: Int) async throws -> PageSummaryRecord? {
    try await store.pageSummary(documentId: documentId, page: page)
  }

  /// OCRed pages without a current summary plus pages without OCR text
  /// (a summary run OCRs those first).
  func pagesNeedingSummary(documentId: String) async throws -> [Int] {
    let needing = try await store.pagesNeedingSummary(documentId: documentId)
    let withoutText = try await store.pageNumbers(documentId: documentId, statuses: [.pending, .failed])
    return Array(Set(needing + withoutText)).sorted()
  }

  func pageSummaryCounts() async throws -> [String: PageSummaryCounts] {
    try await store.pageSummaryCounts()
  }
}
