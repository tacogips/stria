import Foundation
@testable import StriaCore
import Testing

@Suite("ChatStoreTests") struct ChatStoreTests {
  @Test func exchangePersistsInForeignKeyOrderAndHistoryFilters() async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths)
      try await store.insertDocument(storageDocument("doc"))
      let now = Date(timeIntervalSince1970: 1_800_000_020)
      let refs = [PageRef(docId: "doc", page: 2)]
      let exchange = AskExchange(threadId: "thread", newThread: NewChatThread(documentId: "doc", pageNumber: 2, scope: .page),
                                 question: "why?", anchorDocumentId: "doc", anchorPage: 2, assistantStatus: .error,
                                 assistantContent: "redacted error", vendor: "test", model: "m", citations: refs,
                                 run: storageRun("ask-run", documentId: "doc", page: 2, kind: .ask, status: .failed, date: now), createdAt: now)
      try await store.persistAskExchange(exchange)
      let thread = try await store.threadMessages(threadId: "thread")
      #expect(thread.count == 2)
      #expect(thread.map(\.role) == [.user, .assistant])
      #expect(thread.allSatisfy { $0.documentId == "doc" && $0.pageNumber == 2 })
      #expect(thread[1].status == .error)
      #expect(thread[1].citations == refs)
      #expect(try await store.history(documentId: "doc", page: 2, limit: 50).count == 2)
      #expect(try await store.history(documentId: "doc", page: nil, limit: 50).count == 2)
      #expect(try await store.history(documentId: nil, page: nil, limit: 1).map(\.role) == [.assistant])
      #expect(try await store.agentRuns(documentId: "doc").map(\.id) == ["ask-run"])
      do { _ = try await store.history(documentId: nil, page: 2, limit: 5); Issue.record("Expected page filter validation") } catch let error as StriaError { #expect(error.code == .usageError) }
    }
  }

  @Test func libraryWideAskAppearsInHistoryOfCitedDocumentsAndPages() async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths)
      try await store.insertDocument(storageDocument("doc1"))
      try await store.insertDocument(storageDocument("doc2"))
      let now = Date(timeIntervalSince1970: 1_800_000_020)
      try await store.persistAskExchange(AskExchange(
        threadId: "lib", newThread: NewChatThread(documentId: nil, pageNumber: nil, scope: .library), question: "across?",
        anchorDocumentId: nil, anchorPage: nil, assistantStatus: .ok, assistantContent: "answer", vendor: "test", model: nil,
        citations: [PageRef(docId: "doc1", page: 3), PageRef(docId: "doc2", page: 1)],
        run: storageRun("lib-run", documentId: nil, page: nil, kind: .ask, date: now), createdAt: now))
      #expect(try await store.history(documentId: "doc1", page: nil, limit: 50).map(\.role) == [.user, .assistant])
      #expect(try await store.history(documentId: "doc1", page: 3, limit: 50).count == 2)
      #expect(try await store.history(documentId: "doc1", page: 2, limit: 50).isEmpty)
      #expect(try await store.history(documentId: "doc2", page: 1, limit: 50).count == 2)
      #expect(try await store.history(documentId: "doc3", page: nil, limit: 50).isEmpty)
    }
  }

  @Test func threadOverviewsCarryFirstQuestionAndSummaryStaleness() async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths)
      try await store.insertDocument(storageDocument("doc"))
      func exchange(_ question: String, run: String, new: Bool, at seconds: Double) -> AskExchange {
        let date = Date(timeIntervalSince1970: 1_800_000_000 + seconds)
        return AskExchange(threadId: "t1", newThread: new ? NewChatThread(documentId: "doc", pageNumber: 2, scope: .page) : nil,
                           question: question, anchorDocumentId: "doc", anchorPage: 2, assistantStatus: .ok,
                           assistantContent: "answer to \(question)", vendor: "test", model: nil, citations: [],
                           run: storageRun(run, documentId: "doc", page: 2, kind: .ask, date: date), createdAt: date)
      }
      try await store.persistAskExchange(exchange("first question", run: "r1", new: true, at: 10))
      var overview = try #require(try await store.threadOverviews(documentId: "doc", page: nil, limit: 10).first)
      #expect(overview.firstQuestion == "first question")
      #expect(overview.summary == nil)
      #expect(!overview.isSummaryCurrent)
      #expect(overview.messageCount == 2)
      #expect(overview.pageNumber == 2)

      try await store.setThreadSummary(threadId: "t1", summary: "about the first question", throughMessageId: overview.lastMessageId)
      overview = try #require(try await store.threadOverviews(documentId: "doc", page: 2, limit: 10).first)
      #expect(overview.summary == "about the first question")
      #expect(overview.isSummaryCurrent)

      try await store.persistAskExchange(exchange("follow-up", run: "r2", new: false, at: 20))
      overview = try #require(try await store.threadOverviews(documentId: "doc", page: nil, limit: 10).first)
      #expect(overview.firstQuestion == "first question")
      #expect(overview.messageCount == 4)
      #expect(!overview.isSummaryCurrent)
      #expect(try await store.threadOverviews(documentId: "doc", page: 3, limit: 10).isEmpty)
      await #expect(throws: StriaError.self) { try await store.setThreadSummary(threadId: "missing", summary: "x", throughMessageId: 1) }
    }
  }

  @Test func summaryTranscriptKeepsFirstExchangeAndElidesTheMiddle() {
    let messages = (0..<40).map { index in
      ChatMessageRecord(id: Int64(index), threadId: "t", role: index % 2 == 0 ? .user : .assistant, status: .ok,
                        content: String(repeating: "x", count: 100) + " #\(index)", createdAt: Date())
    }
    let text = ThreadSummarizer.transcript(messages, limit: 1_000)
    #expect(text.contains("User: " + String(repeating: "x", count: 100) + " #0"))
    #expect(text.contains("#1\n") || text.contains("#1\n\n"))
    #expect(text.contains("earlier turns omitted"))
    #expect(text.contains("#39"))
    #expect(!text.contains("#10\n"))
    let short = ThreadSummarizer.transcript(Array(messages.prefix(2)))
    #expect(!short.contains("omitted"))
  }
}
