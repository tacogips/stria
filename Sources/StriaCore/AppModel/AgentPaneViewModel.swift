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
  /// Bumped to ask the view to focus the input field (the `/` shortcut).
  public private(set) var focusInputRequest = 0

  public func requestInputFocus() { focusInputRequest += 1 }
  public var notice: String?
  public var historyMode: HistoryMode = .page
  public private(set) var history: [ChatMessageRecord] = []
  public let suggestedQuestions = [
    "Summarize this page",
    "Explain the key terms on this page",
    "What should I read next to understand this?"
  ]

  private let library: StriaLibrary
  private let reader: ReaderViewModel
  private var sendTask: Task<Void, Never>?
  private var historyReloadTask: Task<Void, Never>?
  private let historyDebounce: Duration

  public init(library: StriaLibrary, reader: ReaderViewModel, historyDebounce: Duration = .milliseconds(300)) {
    self.library = library
    self.reader = reader
    self.historyDebounce = historyDebounce
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

  public var vendorConfigured: Bool { library.environment.config.agent.isConfigured }

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
    let request = AskRequest(question: question, context: context, threadId: requestThreadId) { [weak self] chunk in
      Task { @MainActor in self?.appendStreamedChunk(chunk) }
    }
    do {
      _ = try await library.ask(request)
      input = ""
      await reloadTranscript()
      await reloadHistory()
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
      history = try await library.history(
        documentId: reader.documentId,
        page: historyMode == .page ? reader.currentPage : nil
      )
    } catch {
      history = []
    }
  }

  public func selectHistory(_ message: ChatMessageRecord) async {
    threadId = message.threadId
    await reloadTranscript()
    if let page = message.pageNumber { reader.goToPage(page) }
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
