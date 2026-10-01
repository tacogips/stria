import Foundation
import Observation
import PDFKit

public enum SidebarMode: Equatable, Sendable {
  case contents
  case thumbnails
  case search
}

@MainActor
@Observable
public final class ReaderViewModel {
  public let documentId: String
  public private(set) var title = ""
  public private(set) var pageCount = 0
  public private(set) var currentPage = 1
  public var requestedPage: Int?
  public private(set) var outline: [OutlineNode] = []
  public private(set) var currentOutlineNodeID: String?
  public private(set) var pdfDocument: PDFDocument?
  public var sidebarMode: SidebarMode = .contents
  public var searchQuery = ""
  public private(set) var searchResults: [SearchResultItem] = []
  public private(set) var pagesWithoutOCR = 0
  public var pageFieldText = "1"

  private let library: StriaLibrary
  private let debounce: Duration
  private var previousSidebarMode: SidebarMode = .contents
  private var expansionTask: Task<Void, Never>?
  private var readingSaveTask: Task<Void, Never>?

  public init(library: StriaLibrary, documentId: String, debounce: Duration = .seconds(1)) {
    self.library = library
    self.documentId = documentId
    self.debounce = debounce
  }

  public func open() async throws {
    let record = try await library.document(id: documentId)
    guard let pdf = PDFDocument(url: library.originalURL(documentId: documentId)) else {
      throw StriaError.invalidPDF("Could not load the original PDF for \(documentId)")
    }
    title = record.title
    pageCount = record.pageCount
    pdfDocument = pdf
    outline = try await library.outline(documentId: documentId)
    if outline.isEmpty, record.importStatus == .rendering {
      outline = OutlineExtractor.extract(from: pdf)
    }
    requestedPage = min(max(record.lastReadPage ?? 1, 1), max(pageCount, 1))
    updateOutlineSelection()
    expansionTask = Task { [library, documentId] in
      _ = try? await library.expandAllPages(documentId: documentId, concurrency: 2)
    }
  }

  public func close() async {
    expansionTask?.cancel()
    expansionTask = nil
    await flushReadingPosition()
    pdfDocument = nil
  }

  public func pageDidChange(to page: Int) {
    guard pageCount > 0 else { return }
    currentPage = min(max(page, 1), pageCount)
    pageFieldText = String(currentPage)
    updateOutlineSelection()
    readingSaveTask?.cancel()
    let documentId = self.documentId
    let pageToSave = currentPage
    let library = self.library
    readingSaveTask = Task {
      do {
        try await Task.sleep(for: debounce)
        try await library.setLastReadPage(documentId: documentId, page: pageToSave)
      } catch is CancellationError {
        return
      } catch {
        return
      }
      readingSaveTask = nil
    }
  }

  public func goToPage(_ page: Int) {
    guard pageCount > 0 else { return }
    requestedPage = min(max(page, 1), pageCount)
  }

  public func commitPageField() {
    let trimmed = pageFieldText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let page = Int(trimmed) else {
      pageFieldText = String(currentPage)
      return
    }
    goToPage(page)
    pageFieldText = String(requestedPage ?? currentPage)
  }

  public func nextPage() {
    guard currentPage < pageCount else { return }
    goToPage(currentPage + 1)
  }

  public func previousPage() {
    guard currentPage > 1 else { return }
    goToPage(currentPage - 1)
  }

  public func consumeRequestedPage() -> Int? {
    defer { requestedPage = nil }
    return requestedPage
  }

  public func submitSearch(_ query: String) async {
    searchQuery = query
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      clearSearch()
      return
    }
    do {
      let response = try await library.search(query: query, documentId: documentId, limit: 100)
      let counts = try await library.store.ocrCounts(documentId: documentId)
      searchResults = response.results
      pagesWithoutOCR = counts.pending + counts.failed
      if sidebarMode != .search { previousSidebarMode = sidebarMode }
      sidebarMode = .search
    } catch {
      searchResults = []
      pagesWithoutOCR = 0
    }
  }

  public func clearSearch() {
    searchQuery = ""
    searchResults = []
    pagesWithoutOCR = 0
    if sidebarMode == .search { sidebarMode = previousSidebarMode }
  }

  public func flushReadingPosition() async {
    guard let task = readingSaveTask else { return }
    task.cancel()
    readingSaveTask = nil
    do { try await library.setLastReadPage(documentId: documentId, page: currentPage) } catch { }
  }

  func waitForExpansion() async {
    await expansionTask?.value
  }

  private func updateOutlineSelection() {
    currentOutlineNodeID = Self.outlineNodeID(in: outline, page: currentPage)
  }

  static func outlineNodeID(in nodes: [OutlineNode], page: Int) -> String? {
    var candidates: [(id: String, page: Int)] = []
    collectOutline(nodes, prefix: "", into: &candidates)
    return candidates.last(where: { $0.page <= page })?.id
  }

  private static func collectOutline(_ nodes: [OutlineNode], prefix: String, into result: inout [(id: String, page: Int)]) {
    for (index, node) in nodes.enumerated() {
      let id = prefix.isEmpty ? String(index) : "\(prefix).\(index)"
      if let page = node.page { result.append((id, page)) }
      collectOutline(node.children, prefix: id, into: &result)
    }
  }
}
