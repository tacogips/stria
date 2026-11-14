import Foundation
@testable import StriaCore
import Testing

@Suite("ContextSelectorTests") struct ContextSelectorTests {
  @Test func pageNearbyRetrievalAnchorAndLimit() async throws {
    try await withTestDataRoot { paths in
      let store = try await prepareAskDocument(paths: paths, id: "doc", pageCount: 10,
                                               texts: [1: "needle first", 3: "needle third"])
      let config = StriaConfig.defaults.agent
      let selector = ContextSelector(store: store, config: config)
      #expect(try await selector.select(for: AskRequest(question: "unused", context: .page(docId: "doc", page: 2))) == [PageRef(docId: "doc", page: 2)])
      let nearbyConfig = StriaConfig.AgentConfig(vendor: config.vendor, model: config.model, apiKeyEnvironment: config.apiKeyEnvironment,
                                                 neighborPages: 5, maxImages: 4, maxContextCharacters: config.maxContextCharacters,
                                                 systemPrompt: nil)
      let nearby = try await ContextSelector(store: store, config: nearbyConfig)
        .select(for: AskRequest(question: "unused", context: .nearby(docId: "doc", page: 5)))
      #expect(nearby.map(\.page) == [3, 4, 5, 6])
      let retrieved = try await selector.select(for: AskRequest(question: "missing", context: .document(docId: "doc", anchorPage: 2), retrievalQuery: "needle"))
      #expect(retrieved.contains(PageRef(docId: "doc", page: 2)))
      #expect(retrieved.contains(PageRef(docId: "doc", page: 1)) || retrieved.contains(PageRef(docId: "doc", page: 3)))
      do {
        _ = try await selector.select(for: AskRequest(question: "unused", context: .page(docId: "doc", page: 99)))
        Issue.record("Expected missing page error")
      } catch let error as StriaError { #expect(error.code == .pageNotFound) }
      do {
        _ = try await selector.select(for: AskRequest(question: "unused", context: .page(docId: "doc", page: 1), limit: 0))
        Issue.record("Expected invalid cap error")
      } catch let error as StriaError { #expect(error.code == .usageError) }
    }
  }

  @Test func libraryRetrievalAndEmptyResults() async throws {
    try await withTestDataRoot { paths in
      let one = try await prepareAskDocument(paths: paths, id: "doc-one", texts: [1: "transformation text"])
      try await one.insertDocument(storageDocument("doc-two"))
      let image = try askStoredImage()
      try await one.insertPage(documentId: "doc-two", pageNumber: 1, image: image)
      let selector = ContextSelector(store: one, config: StriaConfig.defaults.agent)
      let refs = try await selector.select(for: AskRequest(question: "transformation", context: .library))
      #expect(refs.contains(PageRef(docId: "doc-one", page: 1)))
      do {
        _ = try await selector.select(for: AskRequest(question: "zzzzzzzzzz", context: .library))
        Issue.record("Expected empty retrieval")
      } catch let error as StriaError { #expect(error.code == .noRelevantPages) }
    }
  }

  @Test func libraryRetrievalSpreadsSlotsAcrossDocuments() {
    let ranked = [PageRef(docId: "a", page: 1), PageRef(docId: "a", page: 2), PageRef(docId: "a", page: 3),
                  PageRef(docId: "b", page: 1), PageRef(docId: "c", page: 1)]
    #expect(ContextSelector.spreadAcrossDocuments(ranked, limit: 4) == [
      PageRef(docId: "a", page: 1), PageRef(docId: "a", page: 2), PageRef(docId: "b", page: 1), PageRef(docId: "c", page: 1)
    ])
    #expect(ContextSelector.spreadAcrossDocuments(Array(ranked.prefix(3)), limit: 4) == Array(ranked.prefix(3)))
    #expect(ContextSelector.spreadAcrossDocuments(ranked, limit: 1) == [PageRef(docId: "a", page: 1)])
  }
}
