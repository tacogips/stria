import Foundation

public extension LibraryViewModel {
  var summaryConfigured: Bool { library.environment.config.summary.isConfigured }
  var summaryRunsAfterOCR: Bool { library.environment.config.summary.autoRunAfterOCR }
  var summaryLanguage: String { library.environment.config.summary.language }

  func isSummarizing(_ documentId: String) -> Bool { summaryProgress[documentId] != nil }

  /// "Codex CLI (gpt-6-luna)" style text for the summary run sheet.
  var summaryVendorDescription: String {
    let config = library.environment.config.summary
    guard let vendor = config.vendor else { return "no vendor" }
    return "\(SettingsViewModel.displayName(for: vendor)) (\(config.model ?? "no model"))"
  }

  /// The page's OCR state and tags (the state decides whether it can be summarized).
  func pageInfo(documentId: String, page: Int) async -> PageInfo? {
    try? await library.store.pageInfo(documentId: documentId, page: page)
  }

  /// Summarizes pages chosen like an OCR run: `.remaining` means OCRed pages
  /// without a current summary. Runs for one document queue behind each
  /// other. An invalid page list or an unavailable vendor sets `alert`.
  func summarizePages(documentId: String, range: OCRRange, instruction: String? = nil, language: String? = nil) async {
    guard let row = rows.first(where: { $0.id == documentId }), row.pageCount > 0 else { return }
    let selection: PageSummarySelection
    do {
      switch try range.selection(pageCount: row.pageCount) {
      case .pages(let pages): selection = .pages(pages)
      case .pending, .pendingAndFailed: selection = .missing
      }
    } catch {
      alert = error.message
      return
    }
    await enqueueSummary(documentId: documentId,
                         request: PageSummaryRequest(selection: selection, instruction: instruction, language: language),
                         reportUnavailable: true)
  }

  func pageSummary(documentId: String, page: Int) async -> PageSummaryRecord? {
    try? await library.pageSummary(documentId: documentId, page: page)
  }

  func pagesNeedingSummary(documentId: String) async -> Int {
    (try? await library.pagesNeedingSummary(documentId: documentId).count) ?? 0
  }

  /// Waits for every queued summary run (tests and shutdown).
  func waitForSummaries() async {
    while let entry = summaryTasks.values.first { await entry.task.value }
  }
}

extension LibraryViewModel {
  /// After OCR: summarizes the OCRed pages (nil = every page without a
  /// current summary) when Settings asks for it. Runs in the background.
  func startAutoSummary(documentId: String, pages: [Int]?) {
    guard summaryRunsAfterOCR, summaryConfigured else { return }
    if let pages, pages.isEmpty { return }
    let request = PageSummaryRequest(selection: pages.map { .pages($0) } ?? .missing)
    Task { await enqueueSummary(documentId: documentId, request: request, reportUnavailable: false) }
  }

  func enqueueSummary(documentId: String, request: PageSummaryRequest, reportUnavailable: Bool) async {
    let previous = summaryTasks[documentId]?.task
    let id = UUID()
    let task = Task { [weak self] in
      await previous?.value
      await self?.performSummary(documentId: documentId, request: request, reportUnavailable: reportUnavailable)
      // The last queued run clears the entry before it completes.
      if self?.summaryTasks[documentId]?.id == id { self?.summaryTasks[documentId] = nil }
    }
    summaryTasks[documentId] = (id, task)
    await task.value
  }

  private func performSummary(documentId: String, request: PageSummaryRequest, reportUnavailable: Bool) async {
    summaryProgress[documentId] = PageSummaryProgress(completed: 0, total: 0, currentPage: nil)
    defer {
      summaryProgress[documentId] = nil
      summaryRevision += 1
    }
    do {
      let result = try await library.summarizePages(documentId: documentId, request: request) { [weak self] progress in
        Task { @MainActor in
          guard let self, self.summaryProgress[documentId] != nil else { return }
          self.summaryProgress[documentId] = progress
          self.summaryRevision += 1
        }
      }
      if let reason = result.unavailableReason, reportUnavailable { alert = reason }
    } catch is CancellationError {
      return
    } catch {
      alert = (error as? StriaError)?.message ?? error.localizedDescription
    }
  }
}
