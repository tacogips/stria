import Foundation

public extension StriaLibrary {
  func listDocuments(order: DocumentOrder = .importedDescending) async throws -> [DocumentSummary] {
    try await store.listDocuments(order: order).asyncMap { try await summary(of: $0) }
  }

  func document(id: String) async throws -> DocumentRecord {
    guard let record = try await store.document(id: id) else {
      throw StriaError.documentNotFound("Document not found: \(id)")
    }
    return record
  }

  func summary(of record: DocumentRecord) async throws -> DocumentSummary {
    let counts = try await store.ocrCounts(documentId: record.id)
    let original = paths.root.appendingPathComponent(record.originalPath).standardizedFileURL.path
    return DocumentSummary(id: record.id, title: record.title, pageCount: record.pageCount,
                           importStatus: record.importStatus, importedAt: record.importedAt,
                           originalPath: original, ocr: counts)
  }

  func outline(documentId: String) async throws -> [OutlineNode] {
    let record = try await document(id: documentId)
    guard let outlineJSON = record.outlineJSON else { return [] }
    return OutlineExtractor.decodeJSON(outlineJSON)
  }

  func originalURL(documentId: String) -> URL {
    paths.original(docId: documentId)
  }

  func pageImage(documentId: String, page: Int, output: URL? = nil) async throws -> PageImageResult {
    let record = try await document(id: documentId)
    guard (1...record.pageCount).contains(page),
          let info = try await store.pageInfo(documentId: documentId, page: page),
          let image = try await store.pageImage(documentId: documentId, page: page) else {
      throw StriaError.pageNotFound("Page \(page) not found in document \(documentId)")
    }
    let cache = PageImageCache(paths: paths)
    if let output {
      try cache.write(image: image, to: output)
      return PageImageResult(docId: documentId, page: page, path: output, width: info.width, height: info.height, cached: false)
    }
    if let cachedURL = cache.validCachedURL(docId: documentId, page: page, width: info.width, height: info.height) {
      return PageImageResult(docId: documentId, page: page, path: cachedURL, width: info.width, height: info.height, cached: true)
    }
    let expanded = try cache.expand(docId: documentId, page: page, image: image)
    return PageImageResult(docId: documentId, page: page, path: expanded, width: info.width, height: info.height, cached: false)
  }

  func pageText(documentId: String, page: Int) async throws -> PageInfo {
    guard let info = try await store.pageInfo(documentId: documentId, page: page) else {
      if try await store.document(id: documentId) == nil {
        throw StriaError.documentNotFound("Document not found: \(documentId)")
      }
      throw StriaError.pageNotFound("Page \(page) not found in document \(documentId)")
    }
    return info
  }

  func expandAllPages(documentId: String, concurrency: Int = 2) async throws -> Int {
    let record = try await document(id: documentId)
    let cache = PageImageCache(paths: paths)
    let pages = try await store.pageInfos(documentId: documentId)
    let pending = pages.filter {
      cache.validCachedURL(docId: documentId, page: $0.pageNumber, width: $0.width, height: $0.height) == nil
    }
    guard !pending.isEmpty else { return 0 }
    let width = max(1, concurrency)
    var next = pending.makeIterator()
    return try await withThrowingTaskGroup(of: Int.self) { group in
      for _ in 0..<width {
        guard let info = next.next() else { break }
        group.addTask { try await expandPage(info, document: record, cache: cache) }
      }
      var written = 0
      while let count = try await group.next() {
        written += count
        if Task.isCancelled { group.cancelAll(); break }
        if let info = next.next() { group.addTask { try await expandPage(info, document: record, cache: cache) } }
      }
      return written
    }
  }

  func markOpened(documentId: String) async throws {
    try await store.markOpened(documentId: documentId)
  }

  func setLastReadPage(documentId: String, page: Int) async throws {
    try await store.setLastReadPage(documentId: documentId, page: page)
  }

  private func expandPage(_ info: PageInfo, document: DocumentRecord, cache: PageImageCache) async throws -> Int {
    guard !Task.isCancelled else { return 0 }
    guard let image = try await store.pageImage(documentId: document.id, page: info.pageNumber) else {
      throw StriaError.pageNotFound("Page \(info.pageNumber) not found in document \(document.id)")
    }
    guard !Task.isCancelled else { return 0 }
    _ = try cache.expand(docId: document.id, page: info.pageNumber, image: image)
    return 1
  }
}

private extension Sequence {
  func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
    var values: [T] = []
    for element in self { values.append(try await transform(element)) }
    return values
  }
}
