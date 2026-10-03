import Foundation
import Observation
import PDFKit

public enum SidebarMode: Equatable, Sendable {
  case contents
  case thumbnails
}

/// A zoom command for the PDF view, consumed once per id like `PageNavigation`.
public struct ZoomRequest: Equatable, Sendable {
  public enum Kind: Equatable, Sendable { case zoomIn, zoomOut, actualSize, fitWidth }
  public let id: UUID
  public let kind: Kind
}

/// A scroll command for the PDF view, consumed once per id.
public struct ScrollRequest: Equatable, Sendable {
  public enum Kind: Equatable, Sendable { case pageDown, pageUp, lineDown, lineUp }
  public let id: UUID
  public let kind: Kind
}

/// A flattened outline node with a stable id ("0.2.1" = path of indices), so
/// views can select, expand and scroll to the current section.
public struct OutlineRow: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let page: Int?
  public let children: [OutlineRow]
  public var optionalChildren: [OutlineRow]? { children.isEmpty ? nil : children }

  public static func make(_ nodes: [OutlineNode], prefix: String = "") -> [OutlineRow] {
    nodes.enumerated().map { index, node in
      let id = prefix.isEmpty ? String(index) : "\(prefix).\(index)"
      return OutlineRow(id: id, title: node.title, page: node.page, children: make(node.children, prefix: id))
    }
  }

  /// Ids of every ancestor of `id` ("0.2.1" -> ["0", "0.2"]).
  public static func ancestorIDs(of id: String) -> [String] {
    let parts = id.split(separator: ".")
    guard parts.count > 1 else { return [] }
    return (1..<parts.count).map { parts.prefix($0).joined(separator: ".") }
  }
}

/// One programmatic navigation request. The id makes a repeated request for
/// the same page distinguishable, so the PDF view never has to clear state.
public struct PageNavigation: Equatable, Sendable {
  public let id: UUID
  public let page: Int
}

@MainActor
@Observable
public final class ReaderViewModel {
  public let documentId: String
  public private(set) var title = ""
  public private(set) var pageCount = 0
  public private(set) var currentPage = 1
  public private(set) var navigation: PageNavigation?
  public var requestedPage: Int? { navigation?.page }
  public private(set) var zoom: ZoomRequest?
  public private(set) var scroll: ScrollRequest?
  public private(set) var outline: [OutlineNode] = []
  public private(set) var outlineRows: [OutlineRow] = []
  public private(set) var currentOutlineNodeID: String?
  public private(set) var pdfDocument: PDFDocument?
  public var sidebarMode: SidebarMode = .contents
  public var pageFieldText = "1"

  private let library: StriaLibrary
  private let debounce: Duration
  private var expansionTask: Task<Void, Never>?
  private var readingSaveTask: Task<Void, Never>?

  public init(library: StriaLibrary, documentId: String, debounce: Duration = .seconds(1)) {
    self.library = library
    self.documentId = documentId
    self.debounce = debounce
  }

  public func open() async throws {
    let record = try await library.document(id: documentId)
    let url = library.originalURL(documentId: documentId)
    // PDFDocument(url:) parses the file; keep that off the main actor so the
    // library stays responsive while a large PDF opens.
    let loaded = await Task.detached(priority: .userInitiated) { LoadedPDFDocument(PDFDocument(url: url)) }.value
    guard let pdf = loaded.document else {
      throw StriaError.invalidPDF("Could not load the original PDF for \(documentId)")
    }
    title = record.title
    pageCount = record.pageCount
    pdfDocument = pdf
    outline = try await library.outline(documentId: documentId)
    if outline.isEmpty, record.importStatus == .rendering {
      outline = OutlineExtractor.extract(from: pdf)
    }
    outlineRows = OutlineRow.make(outline)
    navigation = PageNavigation(id: UUID(), page: min(max(record.lastReadPage ?? 1, 1), max(pageCount, 1)))
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
    navigation = PageNavigation(id: UUID(), page: min(max(page, 1), pageCount))
  }

  public func requestZoom(_ kind: ZoomRequest.Kind) {
    zoom = ZoomRequest(id: UUID(), kind: kind)
  }

  public func requestScroll(_ kind: ScrollRequest.Kind) {
    scroll = ScrollRequest(id: UUID(), kind: kind)
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

/// Carries a freshly parsed `PDFDocument` back to the main actor. PDFKit
/// objects are not `Sendable`; nothing else touches the document before it
/// is handed over, so the transfer is safe.
private final class LoadedPDFDocument: @unchecked Sendable {
  let document: PDFDocument?
  init(_ document: PDFDocument?) { self.document = document }
}
