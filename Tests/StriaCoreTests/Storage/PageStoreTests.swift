import Foundation
import StriaCore
import Testing

@Suite("PageStoreTests") struct PageStoreTests {
  @Test func emptyImageBlobRoundTrips() async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths)
      try await store.insertDocument(storageDocument("doc"))
      let empty = StoredPageImage(data: Data(), format: .jpeg, width: 0, height: 0)
      try await store.insertPage(documentId: "doc", pageNumber: 1, image: empty)
      #expect(try await store.pageImage(documentId: "doc", page: 1) == empty)
    }
  }

  @Test func pageImagesAndOCRTransitionsPersist() async throws {
    try await withTestDataRoot { paths in
      let store = try openStorage(paths: paths)
      try await store.insertDocument(storageDocument("doc"))
      let image = storageImage()
      try await store.insertPage(documentId: "doc", pageNumber: 1, image: image)
      try await store.insertPage(documentId: "doc", pageNumber: 2, image: image)
      #expect(try await store.pageNumbers(documentId: "doc") == [1, 2])
      #expect(try await store.pageInfo(documentId: "doc", page: 1)?.ocrStatus == .pending)
      #expect(try await store.pageImage(documentId: "doc", page: 1) == image)
      let success = storageRun("success")
      try await store.recordOCRSuccess(documentId: "doc", page: 1, text: "ＡＢＣ 機械学習", vendor: "test", model: "m", run: success)
      let info = try #require(try await store.pageInfo(documentId: "doc", page: 1))
      #expect(info.ocrStatus == .done)
      #expect(info.ocrText == "ＡＢＣ 機械学習")
      #expect(try await store.search(text: "ABC", documentId: "doc", limit: 10).hits.count == 1)
      let failure = storageRun("failure", status: .failed)
      try await store.recordOCRFailure(documentId: "doc", page: 1, error: "failed", vendor: "test", model: "m", run: failure)
      let failed = try #require(try await store.pageInfo(documentId: "doc", page: 1))
      #expect(failed.ocrStatus == .failed)
      #expect(failed.ocrText == nil)
      #expect(failed.ocrAttempts == 1)
      #expect(try await store.search(text: "ABC", documentId: "doc", limit: 10).hits.isEmpty)
      #expect(try await store.pageNumbers(documentId: "doc", statuses: [.pending, .failed]) == [1, 2])
      #expect(try await store.agentRuns(documentId: "doc").count == 2)
    }
  }
}
