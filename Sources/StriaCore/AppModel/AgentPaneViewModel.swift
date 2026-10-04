import Foundation
import Observation

public enum AgentScope: CaseIterable, Equatable, Sendable {
  case page
  case nearby
  case document
}

public enum HistoryMode: Equatable, Sendable {
  case page
  case document
}

/// Whether a vendor can be used right now.
public enum VendorAvailability: Equatable, Sendable {
  case ready
  /// An API vendor whose credential variable name is not configured.
  case needsCredentialName
  /// An API vendor whose variable is configured but not set in this process.
  case missingKey(String)

  public var isReady: Bool { self == .ready }
}

@MainActor
@Observable
public final class AgentPaneViewModel {
  public var scope: AgentScope = .page
  public var input = ""
  public private(set) var threadId: String?
  public private(set) var transcript: [ChatMessageRecord] = []
  public private(set) var inFlight = false
  /// The partial answer while a request streams; nil otherwise.
  public private(set) var streamingAnswer: String?
  /// The vendor and model used for the next question (chosen in the composer).
  public private(set) var selectedVendor: String?
  public private(set) var selectedModel: String?
  /// Bumped to ask the view to focus the input field (the `/` shortcut).
  public private(set) var focusInputRequest = 0

  public func requestInputFocus() { focusInputRequest += 1 }
  public var notice: String?
  public var historyMode: HistoryMode = .page
  /// Conversations for the History tab (summary + first question).
  public private(set) var threads: [ThreadOverview] = []
  /// Threads whose summary is being written right now.
  public private(set) var summarizingThreadIDs: Set<String> = []
  private let library: StriaLibrary
  private let reader: ReaderViewModel
  private let processEnvironment: [String: String]
  private var sendTask: Task<Void, Never>?
  private var historyReloadTask: Task<Void, Never>?
  private let historyDebounce: Duration

  public init(library: StriaLibrary, reader: ReaderViewModel, historyDebounce: Duration = .milliseconds(300),
              processEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
    self.library = library
    self.reader = reader
    self.historyDebounce = historyDebounce
    self.processEnvironment = processEnvironment
    // Start from config; loadSelection() replaces it with the last chat choice.
    selectedVendor = library.environment.config.agent.vendor
    selectedModel = library.environment.config.agent.model
  }

  public static let vendorOptions = KnownVendors.gateway

  /// Restores the last selection from SQLite (falling back to config).
  public func loadSelection() async {
    if let stored = try? await library.lastAgentSelection() {
      selectedVendor = stored.vendor
      selectedModel = stored.model
    } else if let vendor = library.environment.config.agent.vendor {
      selectedVendor = vendor
      selectedModel = library.environment.config.agent.model
    }
  }

  public func availability(of vendor: String) -> VendorAvailability {
    guard KnownVendors.apiKeyVendors.contains(vendor) else { return .ready }
    guard let name = library.environment.config.agent.credential(for: vendor) else { return .needsCredentialName }
    guard let value = processEnvironment[name], !value.isEmpty else { return .missingKey(name) }
    return .ready
  }

  public func modelOptions(for vendor: String) -> [String] {
    var models = ModelCatalog.models(for: vendor)
    if vendor == selectedVendor, let model = selectedModel, !model.isEmpty, !models.contains(model) { models.append(model) }
    return models
  }

  /// Picks a vendor (only when it is usable) with its default model, and remembers it.
  public func select(vendor: String) async {
    guard availability(of: vendor).isReady else { return }
    selectedVendor = vendor
    selectedModel = ModelCatalog.defaultModel(for: vendor)
    await persistSelection()
  }

  public func select(model: String) async {
    guard selectedVendor != nil else { return }
    selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
    await persistSelection()
  }

  public var selection: AgentSelection? {
    guard let vendor = selectedVendor, let model = selectedModel, !model.isEmpty else { return nil }
    return AgentSelection(vendor: vendor, model: model)
  }

  public var canSend: Bool {
    guard let vendor = selectedVendor else { return false }
    return selection != nil && availability(of: vendor).isReady && !inFlight
  }

  private func persistSelection() async {
    try? await library.setLastAgentSelection(selection ?? selectedVendor.map { AgentSelection(vendor: $0, model: nil) })
  }

  /// Starts `send()` as a cancellable task (the view's Send button).
  public func submit() {
    sendTask = Task { [weak self] in await self?.send() }
  }

  /// Cancels the in-flight question; nothing is persisted for it.
  public func cancel() {
    sendTask?.cancel()
  }

  /// Reloads history after a short pause; page changes while scrolling
  /// collapse into one query, and "This PDF" mode needs none.
  public func scheduleHistoryReload() {
    guard historyMode == .page else { return }
    historyReloadTask?.cancel()
    historyReloadTask = Task { [weak self, historyDebounce] in
      try? await Task.sleep(for: historyDebounce)
      guard !Task.isCancelled else { return }
      await self?.reloadHistory()
    }
  }

  public var vendorConfigured: Bool { selection != nil }

  public var scopeDescription: String {
    let page = reader.currentPage
    switch scope {
    case .page:
      return "Sees page \(page)"
    case .nearby:
      let config = library.environment.config.agent
      let cap = min(max(config.maxImages, 1), 10)
      let low = max(1, page - config.neighborPages)
      let high = min(reader.pageCount, page + config.neighborPages)
      let pages = (low...high).sorted {
        let leftDistance = abs($0 - page)
        let rightDistance = abs($1 - page)
        return leftDistance == rightDistance ? $0 < $1 : leftDistance < rightDistance
      }.prefix(cap).sorted()
      guard let first = pages.first, let last = pages.last else { return "Sees page \(page)" }
      return first == last ? "Sees page \(first)" : "Sees pages \(first)-\(last)"
    case .document:
      return "Sees up to \(library.environment.config.agent.maxImages) relevant pages of \(reader.title), including page \(page)"
    }
  }

  public func send() async {
    let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty, !inFlight else { return }
    guard let selection, availability(of: selection.vendor).isReady else {
      notice = selectedVendor == nil ? "Choose a vendor and model first." : "The selected vendor needs an API key; see Settings."
      return
    }
    inFlight = true
    notice = nil
    let requestThreadId = threadId ?? UUID().uuidString
    threadId = requestThreadId
    let context: AskContext
    switch scope {
    case .page:
      context = .page(docId: reader.documentId, page: reader.currentPage)
    case .nearby:
      context = .nearby(docId: reader.documentId, page: reader.currentPage)
    case .document:
      context = .document(docId: reader.documentId, anchorPage: reader.currentPage)
    }

    streamingAnswer = ""
    // Show the question immediately; the persisted record replaces it.
    transcript.append(ChatMessageRecord(id: Self.pendingMessageID, threadId: requestThreadId, role: .user, status: .ok,
                                        content: question, documentId: reader.documentId, pageNumber: reader.currentPage,
                                        createdAt: Date()))
    let request = AskRequest(question: question, context: context, threadId: requestThreadId, selection: selection) { [weak self] chunk in
      Task { @MainActor in self?.appendStreamedChunk(chunk) }
    }
    do {
      _ = try await library.ask(request)
      input = ""
      await reloadTranscript()
      await reloadHistory()
      if library.environment.config.agent.autoSummarize {
        // Refresh the conversation's summary in the background.
        let selection = self.selection
        Task { [weak self] in await self?.summarize(threadId: requestThreadId, selection: selection) }
      }
    } catch let error as StriaError where error.code == .serviceFailed {
      await reloadTranscript()
      await reloadHistory()
    } catch is CancellationError {
      transcript.removeAll { $0.id == Self.pendingMessageID }
      notice = "Cancelled"
    } catch let error as StriaError where error.code == .serviceUnavailable {
      transcript.removeAll { $0.id == Self.pendingMessageID }
      notice = error.message
    } catch {
      transcript.removeAll { $0.id == Self.pendingMessageID }
      notice = error.localizedDescription
    }
    streamingAnswer = nil
    inFlight = false
  }

  /// Id of the not-yet-persisted user message shown while a question is in flight.
  public static let pendingMessageID: Int64 = -1

  private func appendStreamedChunk(_ chunk: String) {
    guard inFlight else { return }
    streamingAnswer = (streamingAnswer ?? "") + chunk
  }

  public func send(suggestion: String) async {
    input = suggestion
    await send()
  }

  public func newChat() {
    guard !inFlight else { return }
    threadId = nil
    transcript = []
    notice = nil
  }

  public func reloadHistory() async {
    do {
      threads = try await library.threadOverviews(
        documentId: reader.documentId,
        page: historyMode == .page ? reader.currentPage : nil
      )
    } catch {
      threads = []
    }
  }

  /// Opens a conversation from the History tab and jumps to its page.
  public func selectThread(_ thread: ThreadOverview) async {
    threadId = thread.threadId
    await reloadTranscript()
    if thread.documentId == reader.documentId, let page = thread.pageNumber { reader.goToPage(page) }
  }

  /// The page of this PDF where the open conversation's first question was asked.
  public var conversationStartPage: Int? {
    guard let first = transcript.first(where: { $0.role == .user }), first.documentId == reader.documentId else { return nil }
    return first.pageNumber
  }

  /// Jumps the reader to the page where the open conversation started.
  public func goToConversationStart() {
    if let page = conversationStartPage { reader.goToPage(page) }
  }

  /// Reopens an earlier conversation about this PDF to continue it: the most
  /// recent one from a new chat, then each older one on repeated use.
  @discardableResult
  public func resumePreviousChat() async -> Bool {
    guard !inFlight else { return false }
    let candidates: [ThreadOverview]
    do {
      candidates = try await library.threadOverviews(documentId: reader.documentId, page: nil)
    } catch {
      notice = (error as? StriaError)?.message ?? error.localizedDescription
      return false
    }
    let previous: ThreadOverview?
    if let threadId, let index = candidates.firstIndex(where: { $0.threadId == threadId }) {
      previous = candidates.indices.contains(index + 1) ? candidates[index + 1] : nil
    } else {
      previous = candidates.first
    }
    guard let previous else {
      notice = candidates.isEmpty ? "No earlier conversation about this PDF." : "No older conversation about this PDF."
      return false
    }
    notice = nil
    await selectThread(previous)
    return true
  }

  /// Writes (or rewrites) a conversation's summary with the chat's current
  /// vendor and model. Failures leave the previous summary in place.
  public func summarize(threadId: String, selection: AgentSelection? = nil) async {
    guard !summarizingThreadIDs.contains(threadId) else { return }
    summarizingThreadIDs.insert(threadId)
    defer { summarizingThreadIDs.remove(threadId) }
    do {
      _ = try await library.summarizeThread(threadId: threadId, selection: selection ?? self.selection)
    } catch {
      notice = "Could not summarize the conversation: " + ((error as? StriaError)?.message ?? error.localizedDescription)
    }
    await reloadHistory()
  }

  public func citationPages(in message: ChatMessageRecord) -> [Int] {
    var seen = Set<Int>()
    return CitationParser.markers(in: message.content).compactMap { marker in
      guard marker.docId == reader.documentId, seen.insert(marker.page).inserted else { return nil }
      return marker.page
    }
  }

  private func reloadTranscript() async {
    guard let threadId else { transcript = []; return }
    do { transcript = try await library.threadMessages(threadId: threadId) } catch { transcript = [] }
  }
}
