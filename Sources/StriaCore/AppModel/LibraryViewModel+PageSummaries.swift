import Foundation

/// How a document's last summary run ended, for the Summary tab.
public struct PageSummaryRunReport: Equatable, Sendable {
  public enum Outcome: Equatable, Sendable {
    case finished(PageSummaryRunResult)
    case cancelled
    case failed(String)
  }

  public var outcome: Outcome
  public var finishedAt: Date

  public init(outcome: Outcome, finishedAt: Date) {
    self.outcome = outcome
    self.finishedAt = finishedAt
  }

  /// One line such as "3 summarized, 1 failed (p. 4), 2 skipped (no OCR text)".
  public var text: String {
    switch outcome {
    case .cancelled: return "Cancelled."
    case .failed(let message): return "Stopped: \(message)"
    case .finished(let result):
      if let reason = result.unavailableReason { return "Could not summarize: \(reason)" }
      var parts: [String] = []
      if !result.ocred.isEmpty { parts.append("\(result.ocred.count) OCRed first") }
      parts.append("\(result.summarized.count) summarized")
      if !result.failures.isEmpty { parts.append("\(result.failures.count) failed (\(Self.pages(result.failures.map(\.page))))") }
      if !result.ocrFailures.isEmpty { parts.append("OCR failed on \(Self.pages(result.ocrFailures.map(\.page)))") }
      if !result.skipped.isEmpty { parts.append("\(result.skipped.count) skipped (no OCR text: \(Self.pages(result.skipped)))") }
      var line = parts.joined(separator: ", ") + "."
      if let reason = result.ocrUnavailableReason, !result.skipped.isEmpty { line += " " + reason }
      return line
    }
  }

  public var isProblem: Bool {
    switch outcome {
    case .cancelled: return false
    case .failed: return true
    case .finished(let result):
      return result.unavailableReason != nil || !result.failures.isEmpty || !result.skipped.isEmpty || !result.ocrFailures.isEmpty
    }
  }

  private static func pages(_ pages: [Int]) -> String {
    let shown = pages.prefix(5).map { "p. \($0)" }.joined(separator: ", ")
    return pages.count > 5 ? shown + ", …" : shown
  }
}

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

  /// Summarizes pages chosen like an OCR run: `.remaining` means pages
  /// without a current summary. Pages without OCR text are OCRed first.
  /// Runs for one document queue behind each other; an invalid page list
  /// sets `alert`, and every run's outcome lands in `summaryReports`.
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
                         request: PageSummaryRequest(selection: selection, instruction: instruction, language: language))
  }

  /// Stops the running summary run of a document and drops its queued runs.
  /// Pages already summarized keep their summaries.
  func cancelSummaries(documentId: String) {
    summaryGenerations[documentId, default: 0] += 1
    queuedSummaryRuns[documentId] = nil
    runningSummaryWork[documentId]?.cancel()
  }

  func pageSummary(documentId: String, page: Int) async -> PageSummaryRecord? {
    try? await library.pageSummary(documentId: documentId, page: page)
  }

  /// Pages a "Pages without a current summary" run would cover.
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
    let request = PageSummaryRequest(selection: pages.map { .pages($0) } ?? .missing, ocrFirst: false)
    Task { await enqueueSummary(documentId: documentId, request: request) }
  }

  func enqueueSummary(documentId: String, request: PageSummaryRequest) async {
    let previous = summaryTasks[documentId]?.task
    let generation = summaryGenerations[documentId, default: 0]
    let id = UUID()
    if previous != nil { queuedSummaryRuns[documentId, default: 0] += 1 }
    let task = Task { [weak self] in
      await previous?.value
      guard let self else { return }
      if previous != nil, let queued = queuedSummaryRuns[documentId] {
        queuedSummaryRuns[documentId] = queued > 1 ? queued - 1 : nil
      }
      // Cancel drops runs queued before it.
      if summaryGenerations[documentId, default: 0] == generation {
        await performSummary(documentId: documentId, request: request)
      }
      // The last queued run clears the entry before it completes.
      if summaryTasks[documentId]?.id == id { summaryTasks[documentId] = nil }
    }
    summaryTasks[documentId] = (id, task)
    await task.value
  }

  private func performSummary(documentId: String, request: PageSummaryRequest) async {
    setSummaryProgress(documentId, PageSummaryProgress(completed: 0, total: 0, currentPage: nil))
    let library = self.library
    let work = Task {
      try await library.summarizePages(documentId: documentId, request: request) { [weak self] progress in
        Task { @MainActor in
          guard let self, self.summaryProgress[documentId] != nil else { return }
          let phaseChanged = self.summaryProgress[documentId]?.phase != progress.phase
          self.setSummaryProgress(documentId, progress)
          self.summaryRevision += 1
          // OCR done by the run changes the row's OCR counts.
          if phaseChanged { await self.refresh() }
        }
      }
    }
    runningSummaryWork[documentId] = work
    let outcome: PageSummaryRunReport.Outcome
    do {
      outcome = .finished(try await work.value)
    } catch is CancellationError {
      outcome = .cancelled
    } catch {
      outcome = .failed((error as? StriaError)?.message ?? error.localizedDescription)
    }
    runningSummaryWork[documentId] = nil
    summaryReports[documentId] = PageSummaryRunReport(outcome: outcome, finishedAt: Date())
    setSummaryProgress(documentId, nil)
    summaryRevision += 1
    await refresh()
  }

  private func setSummaryProgress(_ documentId: String, _ progress: PageSummaryProgress?) {
    summaryProgress[documentId] = progress
    update(documentId) { $0.summaryProgress = progress }
  }
}
