import Foundation
import StriaCore
import Testing

@Suite @MainActor struct LibraryViewModelTests {
@Test func libraryImportIsIdempotentAndSelectsExistingDocument() async throws {
  try await withAppModelDataRoot { paths in
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one", "two"])
    let model = LibraryViewModel(library: library)
    model.importFiles([source])
    await model.waitForImports()
    #expect(model.rows.count == 1)
    #expect(model.rows[0].pageCount == 2)
    #expect(model.rows[0].rendered == 2)
    #expect(model.rows[0].ocr.done == 2)
    let documentId = try #require(model.rows.first?.id)

    model.selectedID = nil
    model.importFiles([source])
    await model.waitForImports()
    #expect(model.rows.count == 1)
    #expect(model.selectedID == documentId)
  }
}

@Test func removeDeletesRowAndClearsSelection() async throws {
  try await withAppModelDataRoot { paths in
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one"])
    let imported = try await library.importDocument(at: source, runOCR: false)
    let model = LibraryViewModel(library: library)
    await model.refresh()
    model.selectedID = imported.document.id
    await model.remove(documentId: imported.document.id)
    #expect(model.rows.isEmpty)
    #expect(model.selectedID == nil)
    #expect(model.alert == nil)
    await model.remove(documentId: imported.document.id)
    #expect(model.alert != nil)
  }
}

@Test func runOCRRetriesFailedPagesWhenRequested() async throws {
  try await withAppModelDataRoot { paths in
    let ocr = FakeOCRService()
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one"], ocr: ocr)
    let imported = try await library.importDocument(at: source, runOCR: false)
    await ocr.script(docId: imported.document.id, page: 1, .failure(.failed("temporary failure")))
    let model = LibraryViewModel(library: library)
    await model.runOCR(documentId: imported.document.id, retryFailed: false)
    #expect(model.rows.first?.ocr.failed == 1)

    await ocr.script(docId: imported.document.id, page: 1, .success("recovered text"))
    await model.runOCR(documentId: imported.document.id, retryFailed: true)
    #expect(model.rows.first?.ocr.done == 1)
    #expect(await ocr.requests.count == 2)
  }
}

@Test func libraryImportReportsInvalidPDFAndUnavailableOCR() async throws {
  try await withAppModelDataRoot { paths in
    let ocr = FakeOCRService()
    await ocr.setDefault(.failure(.unavailable("OCR credentials are unavailable")))
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one"], ocr: ocr)
    let invalidPDF = paths.root.appendingPathComponent("invalid.pdf")
    try Data("not a PDF".utf8).write(to: invalidPDF)
    let model = LibraryViewModel(library: library)
    model.importFiles([invalidPDF])
    await model.waitForImports()
    #expect(model.alert != nil)
    #expect(model.rows.isEmpty)

    model.alert = nil
    model.importFiles([source])
    await model.waitForImports()
    #expect(model.rows.count == 1)
    #expect(model.rows[0].unavailableReason?.contains("OCR credentials") == true)
  }
}

@Test func appOpenMovesDocumentToTopOfRecents() async throws {
  try await withAppModelDataRoot { paths in
    let clock = AppModelTestClock()
    let (library, firstURL) = try makeAppModelFixture(
      paths: paths, pageTexts: ["first", "second"], filename: "first.pdf", clock: { clock.now() }
    )
    let secondURL = paths.root.appendingPathComponent("second.pdf")
    try SamplePDFFactory.makePDF(at: secondURL, pages: ["second"])
    let first = try await library.importDocument(at: firstURL, runOCR: false)
    let second = try await library.importDocument(at: secondURL, runOCR: false)
    let app = AppModel(library: library, debounce: .zero)
    await app.open(documentId: first.document.id)
    #expect(app.route == .reader(docId: first.document.id))
    app.reader?.pageDidChange(to: 2)
    await app.showLibrary()
    #expect(try await library.document(id: first.document.id).lastReadPage == 2)
    #expect(app.route == .library)
    #expect(app.library.rows.first?.id == first.document.id)
    await app.open(documentId: second.document.id)
    await app.showLibrary()
    #expect(app.library.rows.first?.id == second.document.id)
    #expect(app.library.rows.last?.id == first.document.id)
  }
}
}

@Suite @MainActor struct LibraryThumbnailTests {
  @Test func firstPageThumbnailIsDownscaledAndCached() async throws {
    try await withAppModelDataRoot { paths in
      let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one", "two"])
      let imported = try await library.importDocument(at: source, runOCR: false)
      let image = try #require(try await library.firstPageThumbnail(documentId: imported.document.id, maxPixel: 100))
      #expect(max(image.width, image.height) == 100)
      #expect(try await library.firstPageThumbnail(documentId: "missing", maxPixel: 100) == nil)
      let model = LibraryViewModel(library: library)
      await model.refresh()
      await model.loadThumbnail(documentId: imported.document.id)
      #expect(model.thumbnails[imported.document.id] != nil)
      #expect(max(model.thumbnails[imported.document.id]?.width ?? 0, model.thumbnails[imported.document.id]?.height ?? 0) == LibraryViewModel.thumbnailMaxPixel)
      await model.remove(documentId: imported.document.id)
      #expect(model.thumbnails[imported.document.id] == nil)
    }
  }
}

@Suite @MainActor struct LibraryOCRStateTests {
  @Test func ocrStateAndRerunAllPagesReplacesText() async throws {
    try await withAppModelDataRoot { paths in
      let ocr = FakeOCRService()
      var config = StriaConfig.testing
      config.ocr.autoRunOnImport = false
      let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one", "two"], ocr: ocr, config: config)
      let model = LibraryViewModel(library: library)
      model.importFiles([source])
      await model.waitForImports()
      let id = try #require(model.rows.first?.id)
      #expect(model.rows.first?.ocrState == .notStarted)
      await ocr.script(docId: id, page: 1, .success("first"))
      await ocr.script(docId: id, page: 2, .failure(.failed("boom")))
      await model.runOCR(documentId: id, retryFailed: false)
      #expect(model.rows.first?.ocrState == .hasFailures)
      await ocr.script(docId: id, page: 1, .success("first again"))
      await ocr.script(docId: id, page: 2, .success("second"))
      await model.rerunOCRAllPages(documentId: id)
      #expect(model.rows.first?.ocrState == .complete)
      #expect(try await library.pageText(documentId: id, page: 1).ocrText == "first again")
      #expect(await ocr.requests.count == 4)
    }
  }

  @Test func ocrRunsOnAChosenPageRangeOnly() async throws {
    try await withAppModelDataRoot { paths in
      let ocr = FakeOCRService()
      var config = StriaConfig.testing
      config.ocr.autoRunOnImport = false
      let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one", "two", "three"], ocr: ocr, config: config)
      let model = LibraryViewModel(library: library)
      model.importFiles([source])
      await model.waitForImports()
      let id = try #require(model.rows.first?.id)
      await ocr.script(docId: id, page: 2, .success("two again"))
      await ocr.script(docId: id, page: 3, .success("three again"))
      await model.runOCR(documentId: id, range: .pages(" 2 - 3 "))
      #expect(model.alert == nil)
      #expect(await ocr.requests.map(\.page).sorted() == [2, 3])
      #expect(model.rows.first?.ocr.done == 2)
      #expect(try await library.pageText(documentId: id, page: 3).ocrText == "three again")

      await model.runOCR(documentId: id, range: .pages("4"))
      #expect(model.alert?.contains("exceeds page count 3") == true)
      model.alert = nil
      await model.runOCR(documentId: id, range: .pages("  "))
      #expect(model.alert == "Enter pages such as 1-3, 8")
      #expect(await ocr.requests.count == 2)
    }
  }
}
