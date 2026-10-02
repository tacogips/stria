import Foundation
import StriaCore
import Testing

@Suite("DocumentStoreTests") struct DocumentStoreTests {
  @Test func documentsCanBeFetchedUpdatedAndOrderedByRecency() async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths)
      let older = storageDocument("doc", imported: Date(timeIntervalSince1970: 1_700_000_000))
      let newer = storageDocument("next", imported: Date(timeIntervalSince1970: 1_700_000_100))
      try await store.insertDocument(older)
      try await store.insertDocument(newer)
      #expect(try await store.document(id: "doc") == older)
      #expect(try await store.document(sha256: "sha-doc") == older)
      try await store.markDocumentReady(id: "doc", outlineJSON: "[]")
      try await store.setLastReadPage(documentId: "doc", page: 2)
      try await store.markOpened(documentId: "doc")
      let updated = try #require(try await store.document(id: "doc"))
      #expect(updated.importStatus == .ready)
      #expect(updated.outlineJSON == "[]")
      #expect(updated.lastReadPage == 2)
      #expect(try await store.listDocuments(order: .recents).first?.id == "doc")
      #expect(try await store.listDocuments(order: .importedDescending).first?.id == "next")
    }
  }

  @Test(arguments: [false, true]) func deleteDocumentCascadesPagesSearchAndChats(forceLike: Bool) async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths, like: forceLike)
      try await store.insertDocument(storageDocument("doc"))
      try await store.insertDocument(storageDocument("keep"))
      for doc in ["doc", "keep"] {
        try await store.insertPage(documentId: doc, pageNumber: 1, image: storageImage())
        try await store.recordOCRSuccess(documentId: doc, page: 1, text: "deletable text", vendor: "test", model: nil,
                                         run: storageRun("ocr-\(doc)", documentId: doc, page: 1))
      }
      let now = Date(timeIntervalSince1970: 1_800_000_020)
      try await store.persistAskExchange(AskExchange(
        threadId: "thread", newThread: NewChatThread(documentId: "doc", pageNumber: 1, scope: .page), question: "q",
        anchorDocumentId: "doc", anchorPage: 1, assistantStatus: .ok, assistantContent: "a", vendor: "test", model: nil,
        citations: [PageRef(docId: "doc", page: 1)], run: storageRun("ask-run", documentId: "doc", page: 1, kind: .ask, date: now),
        createdAt: now))

      #expect(try await store.deleteDocument(id: "doc"))
      #expect(try await store.deleteDocument(id: "doc") == false)
      #expect(try await store.document(id: "doc") == nil)
      #expect(try await store.pageInfo(documentId: "doc", page: 1) == nil)
      #expect(try await store.threadMessages(threadId: "thread").isEmpty)
      #expect(try await store.search(text: "deletable text", documentId: nil, limit: 10).hits.map(\.docId) == ["keep"])
      let runs = try await store.agentRuns(documentId: nil)
      #expect(runs.map(\.id).sorted() == ["ask-run", "ocr-doc", "ocr-keep"])
      #expect(runs.first { $0.id == "ask-run" }?.documentId == nil)
      #expect(try await store.document(id: "keep") != nil)
    }
  }
}
