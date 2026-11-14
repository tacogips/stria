import Foundation
import StriaCore
import Testing

@Suite("SearchFacadeTests") struct SearchFacadeTests {
  @Test func searchProvidesImageHintAndRejectsUnknownDocument() async throws {
    try await withTestDataRoot { paths in
      let store = try await prepareAskDocument(paths: paths, id: "doc", texts: [2: "facade searchable phrase"])
      let library = try StriaLibrary.open(environment: makeTestEnvironment(paths: paths))
      let result = try await library.search(query: "searchable", documentId: "doc").results.first
      #expect(result?.page == 2)
      #expect(result?.imagePath.hasSuffix("page-0002.png") == true)
      #expect(result?.imageCached == false)
      let image = try await store.pageImage(documentId: "doc", page: 2)
      guard let image else { Issue.record("Expected stored page image"); return }
      _ = try PageImageCache(paths: paths).expand(docId: "doc", page: 2, image: image)
      #expect(try await library.search(query: "searchable", documentId: "doc").results.first?.imageCached == true)
      do {
        _ = try await library.search(query: "searchable", documentId: "missing")
        Issue.record("Expected unknown document error")
      } catch let error as StriaError { #expect(error.code == .documentNotFound) }
      do {
        _ = try await library.history(documentId: "missing")
        Issue.record("Expected unknown history document error")
      } catch let error as StriaError { #expect(error.code == .documentNotFound) }
    }
  }
}
