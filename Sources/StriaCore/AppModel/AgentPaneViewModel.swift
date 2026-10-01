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

  public init(library: StriaLibrary, reader: ReaderViewModel) {
    self.library = library
    self.reader = reader
  }

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

    do {
      _ = try await library.ask(AskRequest(question: question, context: context, threadId: requestThreadId))
      input = ""
      await reloadTranscript()
      await reloadHistory()
    } catch let error as StriaError where error.code == .serviceFailed {
      await reloadTranscript()
      await reloadHistory()
    } catch let error as StriaError where error.code == .serviceUnavailable {
      notice = error.message
    } catch {
      notice = error.localizedDescription
    }
    inFlight = false
  }

  public func send(suggestion: String) async {
    input = suggestion
    await send()
  }

  public func newChat() {
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
