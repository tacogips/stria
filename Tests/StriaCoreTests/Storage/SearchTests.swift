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
      #expect(english.hits.first?.page == 1)
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

  @Test func crossDocumentHitsAndDocumentFilter() async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths)
      try await store.insertDocument(storageDocument("doc1"))
      try await store.insertDocument(storageDocument("doc2"))
      for (doc, page, text) in [("doc1", 1, "shared phrase"), ("doc1", 2, "ordinary"),
                                ("doc2", 1, "shared phrase"), ("doc2", 2, "unique cross document token")] {
        try await store.insertPage(documentId: doc, pageNumber: page, image: storageImage())
        try await store.recordOCRSuccess(documentId: doc, page: page, text: text, vendor: "test", model: nil,
                                         run: storageRun("\(doc)-\(page)", documentId: doc, page: page))
      }
      let unique = try await store.search(text: "unique cross document token", documentId: nil, limit: 10)
      #expect(unique.hits.map { PageRef(docId: $0.docId, page: $0.page) } == [PageRef(docId: "doc2", page: 2)])
      #expect(unique.hits.count == 1)
      let filtered = try await store.search(text: "shared phrase", documentId: "doc1", limit: 10)
      #expect(!filtered.hits.isEmpty)
      #expect(filtered.hits.allSatisfy { $0.docId == "doc1" })
      let unfiltered = try await store.search(text: "shared phrase", documentId: nil, limit: 10)
      #expect(Set(unfiltered.hits.map(\.docId)) == Set(["doc1", "doc2"]))
    }
  }

  @Test func likeEscapesWildcardsAndMatchesShortQuery() async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths, like: true)
      try await store.insertDocument(storageDocument("doc"))
      for (page, text) in [(1, "50xyoff"), (2, "50%_off")] {
        try await store.insertPage(documentId: "doc", pageNumber: page, image: storageImage())
        try await store.recordOCRSuccess(documentId: "doc", page: page, text: text, vendor: "test", model: nil,
                                         run: storageRun("wild-\(page)", documentId: "doc", page: page))
      }
      let literal = try await store.search(text: "50%_off", documentId: nil, limit: 10)
      #expect(literal.hits.map(\.page) == [2])
      let short = try await store.search(text: "5", documentId: nil, limit: 10)
      #expect(short.matchMode == .like)
      #expect(Set(short.hits.map(\.page)) == Set([1, 2]))
    }
  }

  @Test(arguments: [false, true]) func nfkcMatchesInBothDirections(forceLike: Bool) async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths, like: forceLike)
      try await store.insertDocument(storageDocument("doc"))
      for (page, text) in [(1, "ABC 123"), (2, "ＡＢＣ １２３")] {
        try await store.insertPage(documentId: "doc", pageNumber: page, image: storageImage())
        try await store.recordOCRSuccess(documentId: "doc", page: page, text: text, vendor: "test", model: nil,
                                         run: storageRun("nfkc-\(page)", documentId: "doc", page: page))
      }
      let fullWidthQuery = try await store.search(text: "ＡＢＣ", documentId: nil, limit: 10)
      #expect(Set(fullWidthQuery.hits.map(\.page)) == Set([1, 2]))
      let asciiQuery = try await store.search(text: "ABC", documentId: nil, limit: 10)
      #expect(Set(asciiQuery.hits.map(\.page)) == Set([1, 2]))
    }
  }

  @Test func likeRanksPagesByOccurrenceCount() async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths, like: true)
      try await store.insertDocument(storageDocument("doc"))
      for (page, text) in [(1, "学習 once"), (2, "学習 学習 学習 three times"), (3, "nothing"), (4, "学習 学習 twice")] {
        try await store.insertPage(documentId: "doc", pageNumber: page, image: storageImage())
        try await store.recordOCRSuccess(documentId: "doc", page: page, text: text, vendor: "test", model: nil,
                                         run: storageRun("rank-\(page)", documentId: "doc", page: page))
      }
      let result = try await store.search(text: "学習", documentId: nil, limit: 10)
      #expect(result.matchMode == .like)
      #expect(result.hits.map(\.page) == [2, 4, 1])
      #expect(result.hits.map(\.score) == [3, 2, 1])
    }
  }

  @Test func likeSnippetBracketsTheLiteralMatch() async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths, like: true)
      try await store.insertDocument(storageDocument("doc"))
      try await store.insertPage(documentId: "doc", pageNumber: 1, image: storageImage())
      try await store.recordOCRSuccess(documentId: "doc", page: 1, text: "café then cafe", vendor: "test", model: nil,
                                       run: storageRun("snippet", documentId: "doc", page: 1))
      let result = try await store.search(text: "cafe", documentId: nil, limit: 10)
      #expect(result.hits.first?.snippet.contains("[cafe]") == true)
      #expect(result.hits.first?.snippet.contains("[café]") == false)
    }
  }
}
