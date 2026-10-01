import Foundation

extension StriaLibrary {
  public func search(query: String, documentId: String? = nil, limit: Int = 10) async throws -> SearchResponse {
    if let documentId, try await store.document(id: documentId) == nil {
      throw StriaError.documentNotFound("Document not found: \(documentId)")
    }
    let outcome = try await store.search(text: query, documentId: documentId, limit: limit)
    let results = outcome.hits.map { hit in
      let imageURL = paths.cachedPage(docId: hit.docId, page: hit.page)
      return SearchResultItem(docId: hit.docId, title: hit.title, page: hit.page, snippet: hit.snippet,
                              score: hit.score, imagePath: imageURL.path,
                              imageCached: FileManager.default.fileExists(atPath: imageURL.path))
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
