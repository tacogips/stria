import CoreGraphics
import Foundation
import Observation

/// Where a search looks.
public enum SearchScope: Equatable, Sendable {
  case currentDocument
  case allDocuments
}

/// The app's OCR search: a prompt (popup) opened from the menu or `/`, and a
/// results screen in the center pane with page thumbnails and highlighted
/// context, closed with Esc or the back icon. One instance serves both the
/// library (all PDFs) and the reader (this PDF by default).
@MainActor
@Observable
public final class SearchViewModel {
  public var query = ""
  public var scope: SearchScope = .allDocuments
  public var isPromptPresented = false
  public private(set) var isShowingResults = false
  /// The query and scope the shown results are for.
  public private(set) var resultsQuery = ""
  public private(set) var resultsScope: SearchScope = .allDocuments
  public private(set) var results: [SearchResultItem] = []
  public private(set) var error: String?
  public private(set) var isSearching = false
  public private(set) var thumbnails: [String: CGImage] = [:]
  /// The open document, or nil in the library.
  public private(set) var currentDocumentId: String?
  public private(set) var currentDocumentTitle: String?

  public static let resultLimit = 100
  public static let thumbnailMaxPixel = 200

  private let library: StriaLibrary
  private var thumbnailLoads: Set<String> = []

  public init(library: StriaLibrary) {
    self.library = library
  }

  /// Called when the reader opens or closes a document.
  public func setCurrentDocument(id: String?, title: String?) {
    currentDocumentId = id
    currentDocumentTitle = title
    scope = id == nil ? .allDocuments : .currentDocument
    close()
  }

  public func present() {
    if currentDocumentId == nil { scope = .allDocuments }
    isPromptPresented = true
  }

  public func submit() async {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    isPromptPresented = false
    isSearching = true
    defer { isSearching = false }
    let documentId = scope == .currentDocument ? currentDocumentId : nil
    do {
      results = try await library.search(query: text, documentId: documentId, limit: Self.resultLimit, withContext: true).results
      error = nil
    } catch {
      results = []
      self.error = (error as? StriaError)?.message ?? error.localizedDescription
    }
    resultsQuery = text
    resultsScope = documentId == nil ? .allDocuments : .currentDocument
    isShowingResults = true
  }

  /// Leaves the results screen (Esc or the back icon); the query is kept
  /// for the next search.
  public func close() {
    isShowingResults = false
  }

  public static func thumbnailKey(docId: String, page: Int) -> String { "\(docId)#\(page)" }

  public func loadThumbnail(docId: String, page: Int) async {
    let key = Self.thumbnailKey(docId: docId, page: page)
    guard thumbnails[key] == nil, !thumbnailLoads.contains(key) else { return }
    thumbnailLoads.insert(key)
    defer { thumbnailLoads.remove(key) }
    if let image = try? await library.pageThumbnail(documentId: docId, page: page, maxPixel: Self.thumbnailMaxPixel) {
      thumbnails[key] = image
    }
  }
}
