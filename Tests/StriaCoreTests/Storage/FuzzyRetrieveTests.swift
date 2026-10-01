import Foundation
import StriaCore
import Testing

@Suite("FuzzyRetrieveTests") struct FuzzyRetrieveTests {
  @Test(arguments: [false, true]) func questionRetrievalRanksRelatedPage(forceLike: Bool) async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths, like: forceLike)
      try await store.insertDocument(storageDocument("doc"))
      try await store.insertPage(documentId: "doc", pageNumber: 1, image: storageImage())
      try await store.recordOCRSuccess(documentId: "doc", page: 1, text: "The transformer encoder processes tokens.", vendor: "test", model: nil,
                                       run: storageRun("fuzzy", documentId: "doc", page: 1))
      let refs = try await store.fuzzyRetrieve(question: "What does the transformer encoder do?", documentId: nil, limit: 5)
      #expect(refs.first == PageRef(docId: "doc", page: 1))
      let shortRefs = try await store.fuzzyRetrieve(question: "The tokens", documentId: nil, limit: 5)
      #expect(shortRefs.first == PageRef(docId: "doc", page: 1))
    }
  }
}
