import Foundation
@testable import StriaCore
import Testing

@Suite @MainActor struct ReaderViewModelTests {
@Test func readerPageFieldClampsAndRejectsNonNumericInput() async throws {
  try await withAppModelDataRoot { paths in
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["1", "2", "3", "4", "5"])
    let imported = try await library.importDocument(at: source, runOCR: false)
    let reader = ReaderViewModel(library: library, documentId: imported.document.id, debounce: .milliseconds(10))
    try await reader.open()
    #expect(reader.consumeRequestedPage() == 1)
    reader.previousPage()
    #expect(reader.requestedPage == nil)
    reader.pageFieldText = "7"
    reader.commitPageField()
    #expect(reader.requestedPage == 5)
    #expect(reader.consumeRequestedPage() == 5)
    #expect(reader.requestedPage == nil)
    reader.pageFieldText = "abc"
    reader.commitPageField()
    #expect(reader.requestedPage == nil)
    #expect(reader.pageFieldText == "1")
    reader.pageDidChange(to: 5)
    reader.nextPage()
    #expect(reader.requestedPage == nil)
    reader.previousPage()
    #expect(reader.requestedPage == 4)
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

@Test func readerSearchEntersAndLeavesSearchModeAndExpandsCache() async throws {
  try await withAppModelDataRoot { paths in
    let ocr = FakeOCRService()
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["alpha searchable", "beta"], ocr: ocr)
    let imported = try await library.importDocument(at: source, runOCR: false)
    await ocr.script(docId: imported.document.id, page: 1, .success("alpha searchable"))
    _ = try await library.runOCR(documentId: imported.document.id, selection: .pending)
    let reader = ReaderViewModel(library: library, documentId: imported.document.id)
    reader.sidebarMode = .thumbnails
    try await reader.open()
    await reader.submitSearch("searchable")
    #expect(reader.sidebarMode == .search)
    #expect(reader.searchResults.first?.page == 1)
    reader.clearSearch()
    #expect(reader.sidebarMode == .thumbnails)
    await reader.waitForExpansion()
    #expect(FileManager.default.fileExists(atPath: library.paths.cachedPage(docId: imported.document.id, page: 1).path))
    await reader.close()

    let cacheDirectory = library.paths.cachedPage(docId: imported.document.id, page: 1).deletingLastPathComponent()
    try? FileManager.default.removeItem(at: cacheDirectory)
    let closingReader = ReaderViewModel(library: library, documentId: imported.document.id)
    try await closingReader.open()
    await closingReader.close()
  }
}
}
