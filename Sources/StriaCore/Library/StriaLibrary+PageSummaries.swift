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

  func pagesNeedingSummary(documentId: String) async throws -> [Int] {
    try await store.pagesNeedingSummary(documentId: documentId)
  }
}
