import Foundation
@testable import StriaCore
import Testing

@Suite @MainActor struct ReaderViewModelTests {
@Test func readerLoadsThumbnailsWithoutExpandingPages() async throws {
  try await withAppModelDataRoot { paths in
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["1", "2", "3"])
    let imported = try await library.importDocument(at: source, runOCR: false)
    let reader = ReaderViewModel(library: library, documentId: imported.document.id)
    try await reader.open()
    let thumbnail = try #require(try await reader.thumbnail(page: 2))
    #expect(max(thumbnail.width, thumbnail.height) <= 240)
    await reader.close()
    #expect(reader.pdfDocument == nil)
    for page in 1...3 {
      #expect(!FileManager.default.fileExists(atPath: paths.cachedPage(docId: imported.document.id, page: page).path))
    }
    // Explicit consumers still expand exactly the page they need.
    _ = try await library.pageImage(documentId: imported.document.id, page: 2)
    #expect(FileManager.default.fileExists(atPath: paths.cachedPage(docId: imported.document.id, page: 2).path))
    #expect(!FileManager.default.fileExists(atPath: paths.cachedPage(docId: imported.document.id, page: 1).path))
  }
}

@Test func readerPageFieldClampsAndRejectsNonNumericInput() async throws {
  try await withAppModelDataRoot { paths in
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["1", "2", "3", "4", "5"])
    let imported = try await library.importDocument(at: source, runOCR: false)
    let reader = ReaderViewModel(library: library, documentId: imported.document.id, debounce: .milliseconds(10))
    try await reader.open()
    #expect(reader.requestedPage == 1)
    let opened = reader.navigation
    reader.previousPage()
    #expect(reader.navigation == opened)
    reader.pageFieldText = "7"
    reader.commitPageField()
    #expect(reader.requestedPage == 5)
    #expect(reader.navigation != opened)
    let clamped = reader.navigation
    reader.pageFieldText = "abc"
    reader.commitPageField()
    #expect(reader.navigation == clamped)
    #expect(reader.pageFieldText == "1")
    reader.pageDidChange(to: 5)
    reader.nextPage()
    #expect(reader.navigation == clamped)
    reader.previousPage()
    #expect(reader.requestedPage == 4)
    reader.goToPage(4)
    #expect(reader.requestedPage == 4)
    #expect(reader.navigation?.id != clamped?.id)
    await reader.close()
  }
}

@Test func readerRestoresAndFlushesLastReadPage() async throws {
  try await withAppModelDataRoot { paths in
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["1", "2", "3", "4", "5"])
    let imported = try await library.importDocument(at: source, runOCR: false)
    try await library.setLastReadPage(documentId: imported.document.id, page: 3)
    let reader = ReaderViewModel(library: library, documentId: imported.document.id, debounce: .seconds(5))
    try await reader.open()
    #expect(reader.requestedPage == 3)
    reader.pageDidChange(to: 4)
    await reader.flushReadingPosition()
    #expect(try await library.document(id: imported.document.id).lastReadPage == 4)
    await reader.close()
  }
}

@Test func readerOutlineSelectionUsesPreorderAndPageThreshold() {
  let nodes = [OutlineNode(title: "A", page: 1), OutlineNode(title: "B", page: 3, children: [
    OutlineNode(title: "B1", page: 4)
  ])]
  #expect(ReaderViewModel.outlineNodeID(in: nodes, page: 2) == "0")
  #expect(ReaderViewModel.outlineNodeID(in: nodes, page: 3) == "1")
  #expect(ReaderViewModel.outlineNodeID(in: nodes, page: 5) == "1.0")
}

@Test func searchResultsShowContextAndOpenAtThePage() async throws {
  try await withAppModelDataRoot { paths in
    let ocr = FakeOCRService()
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["alpha searchable", "beta"], ocr: ocr)
    let imported = try await library.importDocument(at: source, runOCR: false)
    await ocr.script(docId: imported.document.id, page: 1, .success("alpha searchable"))
    _ = try await library.runOCR(documentId: imported.document.id, selection: .pending)
    let app = AppModel(library: library)
    await app.open(documentId: imported.document.id)
    let reader = try #require(app.reader)
    let search = app.search
    #expect(search.scope == .currentDocument)
    search.present()
    #expect(search.isPromptPresented)
    search.query = "searchable"
    await search.submit()
    #expect(!search.isPromptPresented)
    #expect(search.isShowingResults)
    #expect(search.resultsQuery == "searchable")
    let hit = try #require(search.results.first)
    #expect(hit.page == 1)
    #expect(hit.context.contains { $0.isHit && $0.text == "searchable" })
    await search.loadThumbnail(docId: hit.docId, page: hit.page)
    #expect(search.thumbnails[SearchViewModel.thumbnailKey(docId: hit.docId, page: 1)] != nil)
    reader.goToPage(2)
    await app.openSearchResult(hit)
    #expect(!search.isShowingResults)
    #expect(reader.requestedPage == 1)
    search.scope = .allDocuments
    await search.submit()
    #expect(search.resultsScope == .allDocuments)
    search.close()
    #expect(!search.isShowingResults)
    #expect(FileManager.default.fileExists(atPath: library.paths.cachedPage(docId: imported.document.id, page: 1).path))
    await reader.close()

    let cacheDirectory = library.paths.cachedPage(docId: imported.document.id, page: 1).deletingLastPathComponent()
    try? FileManager.default.removeItem(at: cacheDirectory)
    let closingReader = ReaderViewModel(library: library, documentId: imported.document.id)
    try await closingReader.open()
    await closingReader.close()
  }
}

@Test func outlineRowsAndZoomRequests() async throws {
  try await withAppModelDataRoot { paths in
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["1", "2"])
    let imported = try await library.importDocument(at: source, runOCR: false)
    let reader = ReaderViewModel(library: library, documentId: imported.document.id)
    try await reader.open()
    #expect(reader.outlineRows.count == reader.outline.count)
    #expect(OutlineRow.ancestorIDs(of: "0.2.1") == ["0", "0.2"])
    #expect(OutlineRow.ancestorIDs(of: "3").isEmpty)
    #expect(reader.zoom == nil)
    reader.requestZoom(.zoomIn)
    let first = reader.zoom
    #expect(first?.kind == .zoomIn)
    reader.requestZoom(.zoomIn)
    #expect(reader.zoom?.id != first?.id)
    await reader.close()
  }
}
}
