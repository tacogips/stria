import Foundation

extension StriaLibrary {
  public func search(query: String, documentId: String? = nil, limit: Int = 10) async throws -> SearchResponse {
    if let documentId, try await store.document(id: documentId) == nil {
      throw StriaError.documentNotFound("Document not found: \(documentId)")
    }
    let outcome = try await store.search(text: query, documentId: documentId, limit: limit)
    let cache = PageImageCache(paths: paths)
    var results: [SearchResultItem] = []
    for hit in outcome.hits {
      let imageURL = paths.cachedPage(docId: hit.docId, page: hit.page)
      let info = try await store.pageInfo(documentId: hit.docId, page: hit.page)
      let cached = info.map { cache.validCachedURL(docId: hit.docId, page: hit.page, width: $0.width, height: $0.height) != nil } ?? false
      results.append(SearchResultItem(docId: hit.docId, title: hit.title, page: hit.page, snippet: hit.snippet,
                                      score: hit.score, imagePath: imageURL.path, imageCached: cached))
    }
    return SearchResponse(query: query, matchMode: outcome.matchMode, results: results)
  }

  public func history(documentId: String? = nil, page: Int? = nil, limit: Int = 50) async throws -> [ChatMessageRecord] {
    if let documentId, try await store.document(id: documentId) == nil {
      throw StriaError.documentNotFound("Document not found: \(documentId)")
    }
    return try await store.history(documentId: documentId, page: page, limit: limit)
  }

  public func threadMessages(threadId: String) async throws -> [ChatMessageRecord] {
    try await store.threadMessages(threadId: threadId)
  }
}
