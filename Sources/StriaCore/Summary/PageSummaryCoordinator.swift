import Foundation

/// Summarizes pages one at a time, in page order, so each page can be read
/// with the previous page's OCR text and its (fresh) summary as context.
struct PageSummaryCoordinator: Sendable {
  let library: StriaLibrary
  static let notConfiguredReason =
    "Page summary vendor is not configured. Choose one in Settings (app) or with `stria config set summary.vendor <vendor>`."
  /// Characters of the target page's text sent to the model.
  static let maxPageCharacters = 24_000
  /// Characters of the previous page's text (its end, which leads into the target).
  static let maxPreviousCharacters = 4_000

  func run(documentId: String, request: PageSummaryRequest,
           onProgress: @escaping @Sendable (PageSummaryProgress) -> Void = { _ in }) async throws -> PageSummaryRunResult {
    if let vendor = library.environment.config.summary.vendor {
      try KnownVendors.requireAvailable(vendor, platform: library.environment.platform)
    }
    guard try await library.store.document(id: documentId) != nil else {
      throw StriaError.documentNotFound("Document not found: \(documentId)")
    }
    let config = library.environment.config
    guard let vendor = config.summary.vendor else {
      return PageSummaryRunResult(docId: documentId, summarized: [], failures: [], skipped: [],
                                  unavailableReason: Self.notConfiguredReason)
    }
    var result = PageSummaryRunResult(docId: documentId, summarized: [], failures: [], skipped: [], unavailableReason: nil)
    if request.ocrFirst { try await ocrMissingText(documentId: documentId, selection: request.selection, into: &result, onProgress: onProgress) }
    let pages = try await selectedPages(documentId: documentId, selection: request.selection)
    let language = request.language ?? config.summary.language
    let instruction = request.instruction?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    let settings = ServiceSettings(vendor: vendor, model: config.summary.model,
                                   apiKeyEnvironment: config.agent.credential(for: vendor),
                                   timeoutSeconds: config.summary.timeoutSeconds)
    let systemPrompt = PageSummaryDefaults.render(config.summary.prompt ?? PageSummaryDefaults.prompt, language: language)

    for (index, page) in pages.enumerated() {
      try Task.checkCancellation()
      onProgress(PageSummaryProgress(phase: .summary, completed: index, total: pages.count, currentPage: page))
      guard let info = try await library.store.pageInfo(documentId: documentId, page: page), info.ocrStatus == .done else {
        result.skipped.append(page)
        continue
      }
      let text = (info.ocrText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      var record = PageSummaryRecord(documentId: documentId, pageNumber: page, status: .done, summary: "", error: nil,
                                     language: language, instruction: instruction, vendor: settings.vendor,
                                     model: settings.model, updatedAt: library.environment.clock())
      if !text.isEmpty {
        let prompt = try await userMessage(documentId: documentId, page: page, text: text, instruction: instruction)
        do {
          let answer = try await library.environment.agentService.ask(AgentRequest(
            question: prompt, systemPrompt: systemPrompt, contextPages: [], history: [], settings: settings
          ))
          record.summary = OCRTextPostProcessor.clean(answer.text)
          if record.summary?.isEmpty == true { throw ServiceError.failed("The summary came back empty") }
        } catch ServiceError.unavailable(let reason) {
          result.unavailableReason = SecretRedactor.truncate(reason)
          return result
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          let message: String
          if case ServiceError.failed(let reason)? = error as? ServiceError { message = reason } else { message = error.localizedDescription }
          record.status = .failed
          record.summary = nil
          record.error = SecretRedactor.truncate(message)
          record.updatedAt = library.environment.clock()
          try await library.store.savePageSummary(record)
          result.failures.append(OCRFailure(page: page, error: record.error ?? message))
          continue
        }
      }
      record.updatedAt = library.environment.clock()
      try await library.store.savePageSummary(record)
      result.summarized.append(page)
    }
    onProgress(PageSummaryProgress(phase: .summary, completed: pages.count, total: pages.count, currentPage: nil))
    return result
  }

  /// OCRs the chosen pages that have no OCR text yet (all such pages for
  /// `.missing`), so they can be summarized in the same run.
  private func ocrMissingText(documentId: String, selection: PageSummarySelection, into result: inout PageSummaryRunResult,
                              onProgress: @escaping @Sendable (PageSummaryProgress) -> Void) async throws {
    let withoutText: [Int]
    switch selection {
    case .missing:
      withoutText = try await library.store.pageNumbers(documentId: documentId, statuses: [.pending, .failed])
    case .pages(let pages):
      let pending = Set(try await library.store.pageNumbers(documentId: documentId, statuses: [.pending, .failed]))
      withoutText = pages.filter(pending.contains).sorted()
    }
    guard !withoutText.isEmpty else { return }
    guard library.environment.config.ocr.isConfigured else {
      result.ocrUnavailableReason = OCRCoordinator.notConfiguredReason
      return
    }
    let counter = ProgressCounter()
    let total = withoutText.count
    onProgress(PageSummaryProgress(phase: .ocr, completed: 0, total: total, currentPage: withoutText.first))
    let summary = try await OCRCoordinator(library: library).run(documentId: documentId, selection: .pages(withoutText)) { _ in
      let done = counter.increment()
      onProgress(PageSummaryProgress(phase: .ocr, completed: done, total: total, currentPage: nil))
    }
    result.ocred = summary.processed.filter { page in !summary.failures.contains { $0.page == page } }
    result.ocrFailures = summary.failures
    result.ocrUnavailableReason = summary.unavailableReason
  }

  private func selectedPages(documentId: String, selection: PageSummarySelection) async throws -> [Int] {
    switch selection {
    case .missing:
      // Pages still without OCR text are listed too, so the run reports them as skipped.
      let needing = try await library.store.pagesNeedingSummary(documentId: documentId)
      let withoutText = try await library.store.pageNumbers(documentId: documentId, statuses: [.pending, .failed])
      return Array(Set(needing + withoutText)).sorted()
    case .pages(let requested):
      let available = Set(try await library.store.pageNumbers(documentId: documentId))
      for page in requested where !available.contains(page) {
        throw StriaError.pageNotFound("Page \(page) not found in document \(documentId)")
      }
      return Array(Set(requested)).sorted()
    }
  }

  /// The previous page (end of its text, and its summary) as context, then
  /// the target page, then any instructions for this run.
  private func userMessage(documentId: String, page: Int, text: String, instruction: String?) async throws -> String {
    var parts: [String] = []
    if page > 1 {
      let previous = try await library.store.pageInfo(documentId: documentId, page: page - 1)
      let previousText = previous?.ocrStatus == .done ? (previous?.ocrText ?? "") : ""
      let previousSummary = try await library.store.pageSummary(documentId: documentId, page: page - 1)
      var block = "<previous_page page=\"\(page - 1)\">\n"
      if !previousText.isEmpty { block += "<text>\n\(String(previousText.suffix(Self.maxPreviousCharacters)))\n</text>\n" }
      if previousSummary?.status == .done, let summary = previousSummary?.summary, !summary.isEmpty {
        block += "<summary>\n\(summary)\n</summary>\n"
      }
      block += "</previous_page>"
      if !previousText.isEmpty || block.contains("<summary>") { parts.append(block) }
    }
    parts.append("<target_page page=\"\(page)\">\n\(String(text.prefix(Self.maxPageCharacters)))\n</target_page>")
    if let instruction { parts.append("Additional instructions for this summary:\n\(instruction)") }
    parts.append("Summarize the target page.")
    return parts.joined(separator: "\n\n")
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Counts OCR progress callbacks, which arrive from concurrent page tasks.
private final class ProgressCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0
  func increment() -> Int {
    lock.lock(); defer { lock.unlock() }
    value += 1
    return value
  }
}
