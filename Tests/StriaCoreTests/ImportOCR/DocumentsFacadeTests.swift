import Foundation
import StriaCore
import Testing

@Suite("DocumentsFacadeTests") struct DocumentsFacadeTests {
  @Test func pageImageCacheOutputValidationAndDocumentSummary() async throws {
    try await withTestDataRoot { paths in
      let (library, source) = try await makeImportFixture(paths: paths, pageTexts: ["one", "two"])
      let imported = try await importFixture(library, source: source)
      let first = try await library.pageImage(documentId: imported.document.id, page: 1)
      #expect(!first.cached)
      #expect(FileManager.default.fileExists(atPath: first.path.path))
      let second = try await library.pageImage(documentId: imported.document.id, page: 1)
      #expect(second.cached)
      let output = paths.root.appendingPathComponent("external/page.png")
      let external = try await library.pageImage(documentId: imported.document.id, page: 2, output: output)
      #expect(!external.cached)
      #expect(FileManager.default.fileExists(atPath: output.path))
      #expect(!FileManager.default.fileExists(atPath: paths.cachedPage(docId: imported.document.id, page: 2).path))
      #expect(try await library.outline(documentId: imported.document.id).isEmpty)
      #expect(library.originalURL(documentId: imported.document.id) == paths.original(docId: imported.document.id))
      let summaries = try await library.listDocuments()
      #expect(summaries.count == 1)
      #expect(summaries[0].originalPath == paths.original(docId: imported.document.id).path)
      #expect(summaries[0].ocr.pending == 2)
      let imagePageError = await #expect(throws: StriaError.self) { try await library.pageImage(documentId: imported.document.id, page: 99) }
      #expect(imagePageError?.code == .pageNotFound)
      let imageDocError = await #expect(throws: StriaError.self) { try await library.pageImage(documentId: "missing", page: 1) }
      #expect(imageDocError?.code == .documentNotFound)
      let textPageError = await #expect(throws: StriaError.self) { try await library.pageText(documentId: imported.document.id, page: 99) }
      #expect(textPageError?.code == .pageNotFound)
    }
  }

  @Test func expandsAllPagesOnceAndPersistsOpenAndReadingState() async throws {
    try await withTestDataRoot { paths in
      let (library, source) = try await makeImportFixture(paths: paths, pageTexts: ["one", "two", "three"])
      let imported = try await importFixture(library, source: source)
      #expect(try await library.expandAllPages(documentId: imported.document.id, concurrency: 2) == 3)
      #expect(try await library.expandAllPages(documentId: imported.document.id, concurrency: 2) == 0)
      try await library.markOpened(documentId: imported.document.id)
      try await library.setLastReadPage(documentId: imported.document.id, page: 2)
      let updated = try #require(try await library.store.document(id: imported.document.id))
      #expect(updated.lastReadPage == 2)
      #expect(updated.lastOpenedAt != nil)
      #expect(try await library.pageText(documentId: imported.document.id, page: 2).ocrStatus == .pending)
    }
  }
}
