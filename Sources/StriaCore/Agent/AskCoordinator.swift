import Foundation

struct AskCoordinator: Sendable {
  private let environment: StriaEnvironment
  private let store: StriaStore

  init(environment: StriaEnvironment, store: StriaStore) {
    self.environment = environment
    self.store = store
  }

  func ask(_ request: AskRequest) async throws -> AskResponse {
    let threadId = request.threadId ?? UUID().uuidString
    let previousMessages = try await store.threadMessages(threadId: threadId)
    let refs = try await selectContext(for: request, previousMessages: previousMessages)
    guard !refs.isEmpty else { throw StriaError.noRelevantPages("No relevant pages were found") }

    let contextPages = try await makeContextPages(refs)
    let history = previousMessages.filter { $0.status == .ok }.map { ChatTurn(role: $0.role, content: $0.content) }
    let thread = previousMessages.isEmpty
      ? NewChatThread(documentId: anchor(for: request.context).docId, pageNumber: anchor(for: request.context).page,
                      scope: scope(for: request.context))
      : nil
    let startedAt = environment.clock()
    let runId = UUID().uuidString
    let settings = ServiceSettings(agent: environment.config.agent)
    let agentRequest = AgentRequest(
      question: request.question,
      systemPrompt: environment.config.agent.systemPrompt ?? AgentDefaults.systemPrompt,
      contextPages: contextPages,
      history: history,
      settings: settings
    )

    let answer: AgentAnswer
    do {
      answer = try await environment.agentService.ask(agentRequest, onChunk: request.onChunk ?? { _ in })
    } catch let error as ServiceError {
      try await handle(error, request: request, refs: refs, threadId: threadId, newThread: thread,
                       runId: runId, settings: settings, startedAt: startedAt)
      throw StriaError.serviceFailed("Ask failed")
    } catch is CancellationError {
      // The user cancelled: no call result to record, nothing persisted.
      throw CancellationError()
    } catch {
      let message = SecretRedactor.truncate(error.localizedDescription)
      let finishedAt = environment.clock()
      let run = makeRun(id: runId, context: request.context, settings: settings, refs: refs,
                        status: .failed, error: message, startedAt: startedAt, finishedAt: finishedAt)
      let anchor = anchor(for: request.context)
      try await store.persistAskExchange(AskExchange(
        threadId: threadId, newThread: thread, question: request.question, anchorDocumentId: anchor.docId,
        anchorPage: anchor.page, assistantStatus: .error, assistantContent: message, vendor: settings.vendor,
        model: settings.model, citations: refs, run: run, createdAt: finishedAt
      ))
      appendRunLog(run)
      throw StriaError.serviceFailed(message)
    }

    let finishedAt = environment.clock()
    let run = makeRun(id: runId, context: request.context, settings: settings, refs: refs,
                      status: .ok, error: nil, startedAt: startedAt, finishedAt: finishedAt)
    let anchor = anchor(for: request.context)
    try await store.persistAskExchange(AskExchange(
      threadId: threadId, newThread: thread, question: request.question, anchorDocumentId: anchor.docId,
      anchorPage: anchor.page, assistantStatus: .ok, assistantContent: answer.text, vendor: settings.vendor,
      model: settings.model, citations: refs, run: run, createdAt: finishedAt
    ))
    appendRunLog(run)
    let sent = contextPages.map { Citation(docId: $0.docId, title: $0.title, page: $0.page, imagePath: $0.pngPath.path) }
    return AskResponse(threadId: threadId, answer: answer.text, vendor: settings.vendor, model: settings.model,
                       runId: runId, citations: AskResponse.citedPages(in: answer.text, contextPages: sent), contextPages: sent)
  }

  /// Fresh retrieval first; in an existing thread the pages the previous
  /// answer cited stay in context, so a follow-up such as "what else is on
  /// that page?" (which retrieves nothing on its own) keeps working.
  private func selectContext(for request: AskRequest, previousMessages: [ChatMessageRecord]) async throws -> [PageRef] {
    let selector = ContextSelector(store: store, config: environment.config.agent)
    let cap = request.limit ?? environment.config.agent.maxImages
    let prior = previousMessages.last { $0.role == .assistant && $0.status == .ok }?.citations ?? []
    let fresh: [PageRef]
    do {
      fresh = try await selector.select(for: request)
    } catch let error as StriaError where error.code == .noRelevantPages && !prior.isEmpty {
      fresh = []
    }
    var merged: [PageRef] = []
    for ref in fresh + prior where !merged.contains(ref) && merged.count < max(1, cap) { merged.append(ref) }
    return merged
  }

  private func handle(
    _ error: ServiceError, request: AskRequest, refs: [PageRef], threadId: String, newThread: NewChatThread?,
    runId: String, settings: ServiceSettings, startedAt: Date
  ) async throws {
    switch error {
    case .unavailable(let reason):
      throw StriaError.serviceUnavailable(SecretRedactor.truncate(reason))
    case .failed(let rawMessage):
      let message = SecretRedactor.truncate(rawMessage)
      let finishedAt = environment.clock()
      let run = makeRun(id: runId, context: request.context, settings: settings, refs: refs,
                        status: .failed, error: message, startedAt: startedAt, finishedAt: finishedAt)
      let anchor = anchor(for: request.context)
      try await store.persistAskExchange(AskExchange(
        threadId: threadId, newThread: newThread, question: request.question, anchorDocumentId: anchor.docId,
        anchorPage: anchor.page, assistantStatus: .error, assistantContent: message, vendor: settings.vendor,
        model: settings.model, citations: refs, run: run, createdAt: finishedAt
      ))
      appendRunLog(run)
      throw StriaError.serviceFailed(message)
    }
  }

  private func makeContextPages(_ refs: [PageRef]) async throws -> [ContextPage] {
    let cache = PageImageCache(paths: environment.paths)
    var pages: [ContextPage] = []
    var remainingCharacters = environment.config.agent.maxContextCharacters
    for ref in refs {
      guard let document = try await store.document(id: ref.docId) else {
        throw StriaError.documentNotFound("Document not found: \(ref.docId)")
      }
      guard let page = try await store.pageInfo(documentId: ref.docId, page: ref.page),
            let image = try await store.pageImage(documentId: ref.docId, page: ref.page) else {
        throw StriaError.pageNotFound("Page \(ref.page) not found in document \(ref.docId)")
      }
      let imageURL: URL
      if let cached = cache.validCachedURL(docId: ref.docId, page: ref.page, width: page.width, height: page.height) {
        imageURL = cached
      } else {
        imageURL = try cache.expand(docId: ref.docId, page: ref.page, image: image)
      }
      let ocrText: String?
      if page.ocrStatus == .done, remainingCharacters > 0 {
        let text = page.ocrText ?? ""
        ocrText = String(text.prefix(remainingCharacters))
        remainingCharacters -= ocrText?.count ?? 0
      } else {
        ocrText = nil
      }
      pages.append(ContextPage(docId: ref.docId, title: document.title, page: ref.page,
                               ocrText: ocrText, pngPath: imageURL))
    }
    return pages
  }

  private func makeRun(
    id: String, context: AskContext, settings: ServiceSettings, refs: [PageRef], status: RunStatus,
    error: String?, startedAt: Date, finishedAt: Date
  ) -> AgentRunRecord {
    let duration = max(0, Int(finishedAt.timeIntervalSince(startedAt) * 1000))
    let anchor = anchor(for: context)
    return AgentRunRecord(id: id, kind: .ask, documentId: anchor.docId, pageNumber: anchor.page,
                          vendor: settings.vendor, model: settings.model, status: status, error: error,
                          imageCount: refs.count, startedAt: startedAt, finishedAt: finishedAt, durationMs: duration)
  }

  private func appendRunLog(_ run: AgentRunRecord) {
    do {
      try RunLogWriter(paths: environment.paths).append(run)
    } catch {
      environment.onRunLogFailure?(error.localizedDescription)
    }
  }

  private func anchor(for context: AskContext) -> (docId: String?, page: Int?) {
    switch context {
    case .page(let docId, let page), .nearby(let docId, let page): (docId, page)
    case .document(let docId, let page): (docId, page)
    case .library: (nil, nil)
    }
  }

  private func scope(for context: AskContext) -> ChatScope {
    switch context {
    case .page: .page
    case .nearby: .nearby
    case .document: .document
    case .library: .library
    }
  }
}
