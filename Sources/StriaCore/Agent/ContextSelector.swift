import Foundation

public struct ContextSelector: Sendable {
  private let store: StriaStore
  private let config: StriaConfig.AgentConfig

  public init(store: StriaStore, config: StriaConfig.AgentConfig) {
    self.store = store
    self.config = config
  }

  public func select(for request: AskRequest) async throws -> [PageRef] {
    let cap = request.limit ?? config.maxImages
    guard (1...10).contains(cap) else { throw StriaError.usage("Ask limit must be between 1 and 10") }
    switch request.context {
    case .page(let docId, let page):
      let document = try await requiredDocument(docId)
      guard (1...document.pageCount).contains(page), try await store.pageInfo(documentId: docId, page: page) != nil else {
        throw StriaError.pageNotFound("Page \(page) not found in document \(docId)")
      }
      return [PageRef(docId: docId, page: page)]
    case .nearby(let docId, let page):
      let document = try await requiredDocument(docId)
      guard (1...document.pageCount).contains(page), try await store.pageInfo(documentId: docId, page: page) != nil else {
        throw StriaError.pageNotFound("Page \(page) not found in document \(docId)")
      }
      let low = max(1, page - config.neighborPages)
      let high = min(document.pageCount, page + config.neighborPages)
      let candidates = (low...high).map { PageRef(docId: docId, page: $0) }
      return Array(candidates.sorted {
        let leftDistance = abs($0.page - page)
        let rightDistance = abs($1.page - page)
        return leftDistance == rightDistance ? $0.page < $1.page : leftDistance < rightDistance
      }.prefix(cap).sorted { $0.page < $1.page })
    case .document(let docId, let anchorPage):
      _ = try await requiredDocument(docId)
      var refs = try await store.fuzzyRetrieve(question: request.retrievalQuery ?? request.question, documentId: docId, limit: cap)
      if let anchorPage {
        guard try await store.pageInfo(documentId: docId, page: anchorPage) != nil else {
          throw StriaError.pageNotFound("Page \(anchorPage) not found in document \(docId)")
        }
        let anchor = PageRef(docId: docId, page: anchorPage)
        if !refs.contains(anchor) {
          if refs.count >= cap { refs.removeLast() }
          refs.append(anchor)
        }
      }
      guard !refs.isEmpty else { throw StriaError.noRelevantPages("No relevant pages were found") }
      return refs
    case .library:
      let candidates = try await store.fuzzyRetrieve(question: request.retrievalQuery ?? request.question,
                                                     documentId: nil, limit: min(100, cap * 4))
      let refs = Self.spreadAcrossDocuments(candidates, limit: cap)
      guard !refs.isEmpty else { throw StriaError.noRelevantPages("No relevant pages were found") }
      return refs
    }
  }

  /// Library-wide retrieval keeps the ranked order but lets no single document
  /// take more than half of the slots while other documents still have hits.
  static func spreadAcrossDocuments(_ ranked: [PageRef], limit: Int) -> [PageRef] {
    let perDocumentCap = max(1, (limit + 1) / 2)
    var counts: [String: Int] = [:]
    var chosen: [PageRef] = []
    var deferred: [PageRef] = []
    for ref in ranked where chosen.count < limit {
      if counts[ref.docId, default: 0] < perDocumentCap {
        counts[ref.docId, default: 0] += 1
        chosen.append(ref)
      } else {
        deferred.append(ref)
      }
    }
    for ref in deferred where chosen.count < limit { chosen.append(ref) }
    return chosen
  }

  private func requiredDocument(_ id: String) async throws -> DocumentRecord {
    guard let document = try await store.document(id: id) else { throw StriaError.documentNotFound("Document not found: \(id)") }
    return document
  }
}
