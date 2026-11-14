import Foundation
import StriaCore
import Testing

@Suite("FuzzyRetrieveTests") struct FuzzyRetrieveTests {
  @Test(arguments: [false, true]) func questionRetrievalRanksRelatedPage(forceLike: Bool) async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths, like: forceLike)
      try await store.insertDocument(storageDocument("doc"))
      try await store.insertPage(documentId: "doc", pageNumber: 1, image: storageImage())
      try await store.recordOCRSuccess(documentId: "doc", page: 1, text: "The transformer attention encoder processes tokens.", vendor: "test", model: nil,
                                       run: storageRun("fuzzy", documentId: "doc", page: 1))
      try await store.insertPage(documentId: "doc", pageNumber: 2, image: storageImage())
      try await store.recordOCRSuccess(documentId: "doc", page: 2, text: "attention only", vendor: "test", model: nil,
                                       run: storageRun("distractor", documentId: "doc", page: 2))
      let refs = try await store.fuzzyRetrieve(question: "What does the transformer encoder do?", documentId: nil, limit: 5)
      #expect(refs.first == PageRef(docId: "doc", page: 1))
      let shortRefs = try await store.fuzzyRetrieve(question: "The tokens", documentId: nil, limit: 5)
      #expect(shortRefs.first == PageRef(docId: "doc", page: 1))
      let ranked = try await store.fuzzyRetrieve(question: "transformer attention mechanism", documentId: nil, limit: 5)
      #expect(ranked.first == PageRef(docId: "doc", page: 1))
    }
  }

  @Test(arguments: [false, true]) func rankingBeatsEarlierDistractor(forceLike: Bool) async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths, like: forceLike)
      try await store.insertDocument(storageDocument("doc"))
      try await store.insertPage(documentId: "doc", pageNumber: 1, image: storageImage())
      try await store.recordOCRSuccess(documentId: "doc", page: 1, text: "attention only", vendor: "test", model: nil,
                                       run: storageRun("rank-distractor", documentId: "doc", page: 1))
      try await store.insertPage(documentId: "doc", pageNumber: 2, image: storageImage())
      try await store.recordOCRSuccess(documentId: "doc", page: 2, text: "transformer attention layers", vendor: "test", model: nil,
                                       run: storageRun("rank-relevant", documentId: "doc", page: 2))
      let ranked = try await store.fuzzyRetrieve(question: "transformer attention mechanism", documentId: nil, limit: 5)
      #expect(ranked.first == PageRef(docId: "doc", page: 2))
    }
  }

  @Test func emptyQuestionIgnoresLimitAndNonEmptyQuestionValidatesLimit() async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths)
      #expect(try await store.fuzzyRetrieve(question: "", documentId: nil, limit: 0).isEmpty)
      #expect(try await store.fuzzyRetrieve(question: "   ", documentId: nil, limit: 101).isEmpty)
      do {
        _ = try await store.fuzzyRetrieve(question: "transformer", documentId: nil, limit: 0)
        Issue.record("Expected invalid limit error")
      } catch let error as StriaError {
        #expect(error.code == .usageError)
      }
    }
  }

  @Test(arguments: [false, true]) func shortTokensRequireEveryToken(forceLike: Bool) async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths, like: forceLike)
      try await store.insertDocument(storageDocument("doc"))
      for (page, text) in [(1, "AI と 学習"), (2, "AI only"), (3, "学習 only")] {
        try await store.insertPage(documentId: "doc", pageNumber: page, image: storageImage())
        try await store.recordOCRSuccess(documentId: "doc", page: page, text: text, vendor: "test", model: nil,
                                         run: storageRun("short-\(page)", documentId: "doc", page: page))
      }
      let refs = try await store.fuzzyRetrieve(question: "AI 学習", documentId: nil, limit: 10)
      #expect(refs == [PageRef(docId: "doc", page: 1)])
    }
  }
}
