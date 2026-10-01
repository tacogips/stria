import Foundation

struct OCRCoordinator: Sendable {
  let library: StriaLibrary

  func run(documentId: String, selection: OCRSelection,
           onProgress: @Sendable (OCRProgress) -> Void = { _ in }) async throws -> OCRRunSummary {
    guard let document = try await library.store.document(id: documentId) else {
      throw StriaError.documentNotFound("Document not found: \(documentId)")
    }
    let pages = try await selectedPages(documentId: documentId, selection: selection)
    let initialCounts = try await library.store.ocrCounts(documentId: documentId)
    guard !pages.isEmpty else {
      return OCRRunSummary(docId: documentId, processed: [], done: initialCounts.done, failed: initialCounts.failed,
                           pending: initialCounts.pending, failures: [], unavailableReason: nil)
    }

    let width = min(max(library.environment.config.ocr.concurrency, 1), 8)
    var remaining = pages.makeIterator()
    var processed: [Int] = []
    var failures: [OCRFailure] = []
    var unavailableReason: String?

    try await withThrowingTaskGroup(of: OCRPageOutcome.self) { group in
      for _ in 0..<width {
        guard let page = remaining.next() else { break }
        group.addTask { try await process(document: document, page: page) }
      }
      while let outcome = try await group.next() {
        if let reason = outcome.unavailableReason {
          unavailableReason = unavailableReason ?? reason
        } else {
          processed.append(outcome.page)
          if let error = outcome.error { failures.append(OCRFailure(page: outcome.page, error: error)) }
          let counts = try await library.store.ocrCounts(documentId: documentId)
          onProgress(OCRProgress(done: counts.done, failed: counts.failed, pending: counts.pending, total: document.pageCount))
        }
        if unavailableReason == nil, let page = remaining.next() {
          group.addTask { try await process(document: document, page: page) }
        }
      }
    }

    let counts = try await library.store.ocrCounts(documentId: documentId)
    return OCRRunSummary(docId: documentId, processed: processed.sorted(), done: counts.done, failed: counts.failed,
                         pending: counts.pending, failures: failures.sorted { $0.page < $1.page }, unavailableReason: unavailableReason)
  }

  private func selectedPages(documentId: String, selection: OCRSelection) async throws -> [Int] {
    switch selection {
    case .pending:
      return try await library.store.pageNumbers(documentId: documentId, statuses: [.pending])
    case .pendingAndFailed:
      return try await library.store.pageNumbers(documentId: documentId, statuses: [.pending, .failed])
    case .pages(let requested):
      let available = Set(try await library.store.pageNumbers(documentId: documentId))
      for page in requested where !available.contains(page) {
        throw StriaError.pageNotFound("Page \(page) not found in document \(documentId)")
      }
      return Array(Set(requested)).sorted()
    }
  }

  private func process(document: DocumentRecord, page: Int) async throws -> OCRPageOutcome {
    let info = try await library.store.pageInfo(documentId: document.id, page: page)
    guard let info else { throw StriaError.pageNotFound("Page \(page) not found in document \(document.id)") }
    let cache = PageImageCache(paths: library.paths)
    let imageURL: URL
    if let cached = cache.validCachedURL(docId: document.id, page: page, width: info.width, height: info.height) {
      imageURL = cached
    } else {
      guard let image = try await library.store.pageImage(documentId: document.id, page: page) else {
        throw StriaError.pageNotFound("Page \(page) not found in document \(document.id)")
      }
      imageURL = try cache.expand(docId: document.id, page: page, image: image)
    }

    let config = library.environment.config.ocr
    let settings = ServiceSettings(ocr: config)
    let start = library.environment.clock()
    let runId = UUID().uuidString
    let result: OCRResult
    do {
      result = try await library.environment.ocrService.recognize(
        OCRRequest(docId: document.id, page: page, pngPath: imageURL, prompt: config.prompt ?? OCRDefaults.prompt, settings: settings)
      )
    } catch ServiceError.unavailable(let reason) {
      return OCRPageOutcome(page: page, error: nil, unavailableReason: reason)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      let message: String
      if let serviceError = error as? ServiceError, case .failed(let failure) = serviceError {
        message = failure
      } else {
        message = error.localizedDescription
      }
      let safeMessage = SecretRedactor.truncate(message)
      let finish = library.environment.clock()
      let run = makeRun(id: runId, document: document, page: page, settings: settings, status: .failed,
                        error: safeMessage, start: start, finish: finish)
      try await library.store.recordOCRFailure(documentId: document.id, page: page, error: safeMessage,
                                               vendor: settings.vendor, model: settings.model, run: run)
      appendLog(run)
      return OCRPageOutcome(page: page, error: safeMessage, unavailableReason: nil)
    }
    let finish = library.environment.clock()
    let run = makeRun(id: runId, document: document, page: page, settings: settings, status: .ok, error: nil, start: start, finish: finish)
    try await library.store.recordOCRSuccess(documentId: document.id, page: page,
                                             text: OCRTextPostProcessor.clean(result.text), vendor: settings.vendor,
                                             model: settings.model, run: run)
    appendLog(run)
    return OCRPageOutcome(page: page, error: nil, unavailableReason: nil)
  }

  private func makeRun(id: String, document: DocumentRecord, page: Int, settings: ServiceSettings,
                       status: RunStatus, error: String?, start: Date, finish: Date) -> AgentRunRecord {
    let duration = max(0, Int(finish.timeIntervalSince(start) * 1000))
    return AgentRunRecord(id: id, kind: .ocr, documentId: document.id, pageNumber: page, vendor: settings.vendor,
                          model: settings.model, status: status, error: error, imageCount: 1, startedAt: start,
                          finishedAt: finish, durationMs: duration)
  }

  private func appendLog(_ run: AgentRunRecord) {
    do {
      try RunLogWriter(paths: library.paths).append(run)
    } catch {
      library.environment.onRunLogFailure?(error.localizedDescription)
    }
  }
}

private struct OCRPageOutcome: Sendable {
  let page: Int
  let error: String?
  let unavailableReason: String?
}
