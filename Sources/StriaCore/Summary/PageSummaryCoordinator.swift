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
           onProgress: @Sendable (PageSummaryProgress) -> Void = { _ in }) async throws -> PageSummaryRunResult {
    guard try await library.store.document(id: documentId) != nil else {
      throw StriaError.documentNotFound("Document not found: \(documentId)")
    }
    let pages = try await selectedPages(documentId: documentId, selection: request.selection)
    let config = library.environment.config
    guard let vendor = config.summary.vendor else {
      return PageSummaryRunResult(docId: documentId, summarized: [], failures: [], skipped: [],
                                  unavailableReason: Self.notConfiguredReason)
    }
    let language = request.language ?? config.summary.language
    let instruction = request.instruction?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    let settings = ServiceSettings(vendor: vendor, model: config.summary.model,
                                   apiKeyEnvironment: config.agent.credential(for: vendor),
                                   timeoutSeconds: config.summary.timeoutSeconds)
    let systemPrompt = PageSummaryDefaults.render(config.summary.prompt ?? PageSummaryDefaults.prompt, language: language)

    var summarized: [Int] = []
    var failures: [OCRFailure] = []
    var skipped: [Int] = []
    for (index, page) in pages.enumerated() {
      try Task.checkCancellation()
      onProgress(PageSummaryProgress(completed: index, total: pages.count, currentPage: page))
      guard let info = try await library.store.pageInfo(documentId: documentId, page: page), info.ocrStatus == .done else {
        skipped.append(page)
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
          return PageSummaryRunResult(docId: documentId, summarized: summarized, failures: failures, skipped: skipped,
                                      unavailableReason: SecretRedactor.truncate(reason))
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
          failures.append(OCRFailure(page: page, error: record.error ?? message))
          continue
        }
      }
      record.updatedAt = library.environment.clock()
      try await library.store.savePageSummary(record)
      summarized.append(page)
    }
    onProgress(PageSummaryProgress(completed: pages.count, total: pages.count, currentPage: nil))
    return PageSummaryRunResult(docId: documentId, summarized: summarized, failures: failures, skipped: skipped,
                                unavailableReason: nil)
  }

  private func selectedPages(documentId: String, selection: PageSummarySelection) async throws -> [Int] {
    switch selection {
    case .missing:
      return try await library.store.pagesNeedingSummary(documentId: documentId)
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
