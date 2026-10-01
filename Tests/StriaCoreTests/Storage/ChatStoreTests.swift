import Foundation
import StriaCore
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
}
