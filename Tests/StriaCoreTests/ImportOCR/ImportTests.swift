import Foundation
import PDFKit
import StriaCore
import Testing

@Suite("ImportTests") struct ImportTests {
  @Test func emitsCopiedOnlyAfterRowAndRendersPagesInOrder() async throws {
    try await withTestDataRoot { paths in
      let (library, source) = try await makeImportFixture(paths: paths, pageTexts: ["one", "two", "three"])
      var events: [ImportEvent] = []
      for await event in library.importEvents(at: source, runOCR: false) {
        if case .copied(let id) = event { #expect(try await library.store.document(id: id) != nil) }
        events.append(event)
      }
      let rendered = events.compactMap { event -> Int? in if case .rendered(let page, _) = event { return page }; return nil }
      #expect(rendered == [1, 2, 3])
      #expect(events.first.map { if case .copied = $0 { true } else { false } } == true)
      #expect(events.last.map { if case .finished = $0 { true } else { false } } == true)
      let result = try #require(events.compactMap { if case .finished(let result) = $0 { result } else { nil } }.first)
      #expect(!result.alreadyImported)
      #expect(result.document.pageCount == 3)
      #expect(result.document.importStatus == .ready)
      #expect(result.ocr.status == .skipped)
      #expect(result.ocr.pending == 3)
      #expect(try Data(contentsOf: library.originalURL(documentId: result.document.id)) == Data(contentsOf: source))
      #expect(try await library.store.pageNumbers(documentId: result.document.id) == [1, 2, 3])
    }
  }

  @Test func sameBytesAreIdempotentAndInterruptedRenderingResumes() async throws {
    try await withTestDataRoot { paths in
      let (library, source) = try await makeImportFixture(paths: paths, pageTexts: ["one", "two", "three"])
      let first = try await importFixture(library, source: source)
      let repeatResult = try await importFixture(library, source: source)
      #expect(repeatResult.alreadyImported)
      #expect(try await library.store.pageNumbers(documentId: first.document.id).count == 3)

      let partialURL = paths.root.appendingPathComponent("partial.pdf")
      try SamplePDFFactory.makePDF(at: partialURL, pages: ["a", "b", "c"])
      let sha = try DocumentIdentity.sha256Hex(of: partialURL)
      let id = DocumentIdentity.docId(sha256Hex: sha)
      let original = paths.original(docId: id)
      try FileManager.default.createDirectory(at: paths.originals, withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: partialURL, to: original)
      let date = Date(timeIntervalSince1970: 1_800_000_000)
      try await library.store.insertDocument(DocumentRecord(id: id, sha256: sha, title: "partial", originalFilename: "partial.pdf",
        originalPath: "originals/\(id).pdf", byteSize: 1, pageCount: 3, importStatus: .rendering, renderDPI: 150,
        imageFormat: .heic, importedAt: date, updatedAt: date))
      let pdf = try #require(PDFDocument(url: partialURL))
      let page = try #require(pdf.page(at: 0))
      let bitmap = try PageRenderer.render(page: page, dpi: 150, maxPixelDimension: 4096)
      try await library.store.insertPage(documentId: id, pageNumber: 1,
        image: ImageCodec.encode(bitmap, preferred: .jpeg, quality: 0.75))
      let resumed = try await importFixture(library, source: partialURL)
      #expect(resumed.alreadyImported)
      #expect(resumed.document.importStatus == .ready)
      #expect(try await library.store.pageNumbers(documentId: id) == [1, 2, 3])
    }
  }

  @Test func unavailableOCRKeepsPagesPendingWithoutRunsAndPageFailureIsPartial() async throws {
    try await withTestDataRoot { paths in
      let fake = FakeOCRService()
      let (library, source) = try await makeImportFixture(paths: paths, pageTexts: ["a", "b", "c"], ocr: fake)
      await fake.setDefault(.failure(.unavailable("environment variable KEY is not set")))
      let unavailable = try await importFixture(library, source: source, runOCR: true)
      #expect(unavailable.ocr.status == .unavailable)
      #expect(unavailable.ocr.reason == "environment variable KEY is not set")
      #expect(unavailable.ocr.pending == 3)
      #expect(try await library.store.agentRuns(documentId: unavailable.document.id).isEmpty)

      let secondFake = FakeOCRService()
      let (secondLibrary, secondSource) = try await makeImportFixture(paths: paths, pageTexts: ["x", "y"], ocr: secondFake)
      let otherId = DocumentIdentity.docId(sha256Hex: try DocumentIdentity.sha256Hex(of: secondSource))
      await secondFake.script(docId: otherId, page: 1, .failure(.failed(String(repeating: "e", count: 3000))))
      let partial = try await importFixture(secondLibrary, source: secondSource, runOCR: true)
      #expect(partial.ocr.status == .partial)
      #expect(partial.ocr.failed == 1)
      #expect(partial.ocr.done == 1)
      #expect(try await secondLibrary.store.pageInfo(documentId: otherId, page: 1)?.ocrError?.count == 2000)
    }
  }

  @Test func fakeOCRCompletesImportAndIndexesExtractedText() async throws {
    try await withTestDataRoot { paths in
      let (library, source) = try await makeImportFixture(paths: paths, pageTexts: ["first", "second"])
      let result = try await importFixture(library, source: source, runOCR: true)
      #expect(result.ocr.status == .completed)
      #expect(result.ocr.done == 2)
      let matches = try await library.store.search(text: "text \(result.document.id) p2", documentId: result.document.id, limit: 10)
      #expect(matches.hits.contains { $0.page == 2 })
    }
  }

  @Test func invalidPDFCopyFailureAndIdCollisionLeaveNoNewDocument() async throws {
    try await withTestDataRoot { paths in
      let (library, source) = try await makeImportFixture(paths: paths, pageTexts: ["valid"])
      let invalid = paths.root.appendingPathComponent("invalid.pdf")
      try SamplePDFFactory.writeNotAPDF(at: invalid)
      let invalidError = await #expect(throws: StriaError.self) { try await library.importDocument(at: invalid, runOCR: false) }
      #expect(invalidError?.code == .invalidPDF)
      #expect(try FileManager.default.contentsOfDirectory(atPath: paths.originals.path).isEmpty)
      #expect(try await library.store.listDocuments(order: .importedDescending).isEmpty)

      let collisionSource = paths.root.appendingPathComponent("collision.pdf")
      try SamplePDFFactory.makePDF(at: collisionSource, pages: ["collision"])
      let sha = try DocumentIdentity.sha256Hex(of: collisionSource)
      let id = DocumentIdentity.docId(sha256Hex: sha)
      let date = Date(timeIntervalSince1970: 1_800_000_000)
      try await library.store.insertDocument(DocumentRecord(id: id, sha256: "different-\(sha)", title: "seed", originalFilename: "seed.pdf",
        originalPath: "originals/seed.pdf", byteSize: 1, pageCount: 1, importStatus: .rendering, renderDPI: 150,
        imageFormat: .heic, importedAt: date, updatedAt: date))
      let collision = await #expect(throws: StriaError.self) { try await library.importDocument(at: collisionSource, runOCR: false) }
      #expect(collision?.code == .idCollision)

      let failSource = paths.root.appendingPathComponent("copy-failure.pdf")
      try SamplePDFFactory.makePDF(at: failSource, pages: ["copy"])
      try FileManager.default.removeItem(at: paths.originals)
      try Data("not a directory".utf8).write(to: paths.originals)
      let copyFailure = await #expect(throws: StriaError.self) { try await library.importDocument(at: failSource, runOCR: false) }
      #expect(copyFailure?.code == .ioError)
      let failId = DocumentIdentity.docId(sha256Hex: try DocumentIdentity.sha256Hex(of: failSource))
      #expect(try await library.store.document(id: failId) == nil)
      #expect(try FileManager.default.contentsOfDirectory(atPath: paths.root.path).contains("originals"))
      _ = source
    }
  }

  @Test func concurrentImportsOfSameBytesKeepTheOriginal() async throws {
    try await withTestDataRoot { paths in
      let (library, source) = try await makeImportFixture(paths: paths, pageTexts: ["one", "two"])
      let sourceBytes = try Data(contentsOf: source)
      let id = DocumentIdentity.docId(sha256Hex: try DocumentIdentity.sha256Hex(of: source))
      var copies: [URL] = []
      for index in 0..<6 {
        let copy = paths.root.appendingPathComponent("copy \(index).pdf")
        try FileManager.default.copyItem(at: source, to: copy)
        copies.append(copy)
      }
      let successes = await withTaskGroup(of: Bool.self) { group in
        for copy in copies {
          group.addTask { (try? await library.importDocument(at: copy, runOCR: false)) != nil }
        }
        var count = 0
        for await succeeded in group where succeeded { count += 1 }
        return count
      }
      #expect(successes >= 1)
      #expect(FileManager.default.fileExists(atPath: paths.original(docId: id).path))
      #expect(try Data(contentsOf: paths.original(docId: id)) == sourceBytes)
      #expect(try await library.store.document(id: id)?.importStatus == .ready)
    }
  }
}
