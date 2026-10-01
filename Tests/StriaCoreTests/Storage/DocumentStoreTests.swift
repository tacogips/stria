import Foundation
import StriaCore
import Testing

@Suite("DocumentStoreTests") struct DocumentStoreTests {
  @Test func documentsCanBeFetchedUpdatedAndOrderedByRecency() async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths)
      let older = storageDocument("doc", imported: Date(timeIntervalSince1970: 1_700_000_000))
      let newer = storageDocument("next", imported: Date(timeIntervalSince1970: 1_700_000_100))
      try await store.insertDocument(older)
      try await store.insertDocument(newer)
      #expect(try await store.document(id: "doc") == older)
      #expect(try await store.document(sha256: "sha-doc") == older)
      try await store.markDocumentReady(id: "doc", outlineJSON: "[]")
      try await store.setLastReadPage(documentId: "doc", page: 2)
      try await store.markOpened(documentId: "doc")
      let updated = try #require(try await store.document(id: "doc"))
      #expect(updated.importStatus == .ready)
      #expect(updated.outlineJSON == "[]")
      #expect(updated.lastReadPage == 2)
      #expect(try await store.listDocuments(order: .recents).first?.id == "doc")
      #expect(try await store.listDocuments(order: .importedDescending).first?.id == "next")
    }
  }
}
