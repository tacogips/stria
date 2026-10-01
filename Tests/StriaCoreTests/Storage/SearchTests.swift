import Foundation
import StriaCore
import Testing

@Suite("SearchTests") struct SearchTests {
  @Test(arguments: [false, true]) func searchSupportsFTSAndLike(forceLike: Bool) async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths, like: forceLike)
      let d1 = storageDocument("doc1")
      let d2 = storageDocument("doc2")
      try await store.insertDocument(d1)
      try await store.insertDocument(d2)
      for (doc, page, text) in [("doc1", 1, "ordinary page with transformer and 機械学習"),
                                ("doc2", 2, "50%_off exact ＡＢＣ 学習") ] {
        try await store.insertPage(documentId: doc, pageNumber: page, image: storageImage())
        try await store.recordOCRSuccess(documentId: doc, page: page, text: text, vendor: "test", model: nil,
                                         run: storageRun(UUID().uuidString, documentId: doc, page: page))
      }
      let english = try await store.search(text: "transformer", documentId: nil, limit: 10)
      #expect(english.hits.first?.docId == "doc1")
      #expect(english.matchMode == (forceLike ? .like : (await store.searchBackend == .fts5 ? .fts : .like)))
      let japanese = try await store.search(text: "機械学習", documentId: nil, limit: 10)
      #expect(japanese.hits.first?.docId == "doc1")
      let short = try await store.search(text: "学習", documentId: nil, limit: 10)
      #expect(short.matchMode == .like)
      #expect(short.hits.contains { $0.docId == "doc2" })
      let escaped = try await store.search(text: "50%_off", documentId: nil, limit: 10)
      #expect(escaped.hits.map(\.docId) == ["doc2"])
      let normalized = try await store.search(text: "ＡＢＣ", documentId: nil, limit: 10)
      #expect(normalized.hits.map(\.docId) == ["doc2"])
      let filtered = try await store.search(text: "page", documentId: "doc1", limit: 10)
      #expect(filtered.hits.allSatisfy { $0.docId == "doc1" })
      do { _ = try await store.search(text: " ", documentId: nil, limit: 10); Issue.record("Expected empty query error") } catch let error as StriaError { #expect(error.code == .usageError) }
      do { _ = try await store.search(text: "word", documentId: nil, limit: 0); Issue.record("Expected invalid limit error") } catch let error as StriaError { #expect(error.code == .usageError) }
    }
  }
}
