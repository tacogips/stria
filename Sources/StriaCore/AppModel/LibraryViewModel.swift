import Foundation
import Observation

public struct LibraryRow: Identifiable, Equatable, Sendable {
  public let id: String
  public var title: String
  public var pageCount: Int
  public var importStatus: ImportStatus
  public var rendered: Int
  public var ocr: OCRCounts
  public var unavailableReason: String?
  public var lastOpenedAt: Date?
  /// True while this app process is rendering or OCRing the document.
  public var isBusy: Bool

  public init(id: String, title: String, pageCount: Int, importStatus: ImportStatus, rendered: Int,
              ocr: OCRCounts, unavailableReason: String? = nil, lastOpenedAt: Date? = nil, isBusy: Bool = false) {
    self.id = id
    self.title = title
    self.pageCount = pageCount
    self.importStatus = importStatus
    self.rendered = rendered
    self.ocr = ocr
    self.unavailableReason = unavailableReason
    self.lastOpenedAt = lastOpenedAt
    self.isBusy = isBusy
  }
}

@MainActor
@Observable
public final class LibraryViewModel {
  public private(set) var rows: [LibraryRow] = []
  public var alert: String?
  public private(set) var isImporting = false
  public var selectedID: String?
  /// OCR search across every document, shown in place of the list.
  public var searchQuery = ""
  public private(set) var searchResults: [SearchResultItem] = []
  public private(set) var searchError: String?
  public private(set) var isSearching = false

  private let library: StriaLibrary
  private var importTasks: [UUID: Task<Void, Never>] = [:]
  private var unavailableReasons: [String: String] = [:]
  private var renderedPages: [String: Int] = [:]
  private var busyIDs: Set<String> = []

  public init(library: StriaLibrary) {
    self.library = library
  }

  public func refresh() async {
    do {
      var refreshedRows: [LibraryRow] = []
      for record in try await library.store.listDocuments(order: .recents) {
        let summary = try await library.summary(of: record)
        refreshedRows.append(LibraryRow(
          id: summary.id,
          title: summary.title,
          pageCount: summary.pageCount,
          importStatus: summary.importStatus,
          rendered: renderedPages[summary.id] ?? (summary.importStatus == .ready ? summary.pageCount : 0),
          ocr: summary.ocr,
          unavailableReason: unavailableReasons[summary.id]
            ?? (summary.ocr.pending > 0 && !library.environment.config.ocr.isConfigured ? "not configured" : nil),
          lastOpenedAt: record.lastOpenedAt,
          isBusy: busyIDs.contains(summary.id)
        ))
      }
      rows = refreshedRows
    } catch {
      alert = error.localizedDescription
    }
  }

  public func importFiles(_ urls: [URL]) {
    for url in urls {
      let taskID = UUID()
      let task = Task { [weak self] in
        guard let self else { return }
        await self.consumeImport(at: url)
        self.importTasks[taskID] = nil
        self.isImporting = !self.importTasks.isEmpty
      }
      importTasks[taskID] = task
    }
    isImporting = !importTasks.isEmpty
  }

  public func runOCR(documentId: String, retryFailed: Bool) async {
    setBusy(documentId, true)
    defer { setBusy(documentId, false) }
    do {
      let summary = try await library.runOCR(
        documentId: documentId,
        selection: retryFailed ? .pendingAndFailed : .pending
      )
      if let reason = summary.unavailableReason {
        unavailableReasons[documentId] = reason
      } else {
        unavailableReasons[documentId] = nil
      }
      await refresh()
    } catch {
      alert = error.localizedDescription
    }
  }

  /// Whether OCR and the agent have a vendor; the library banner points to
  /// Settings while either is missing.
  public var ocrConfigured: Bool { library.environment.config.ocr.isConfigured }
  public var agentConfigured: Bool { library.environment.config.agent.isConfigured }
  public var ocrRunsAutomatically: Bool { library.environment.config.ocr.autoRunOnImport }

  public func submitSearch() async {
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { clearSearch(); return }
    do {
      searchResults = try await library.search(query: query, documentId: nil, limit: 100).results
      searchError = nil
    } catch {
      searchResults = []
      searchError = (error as? StriaError)?.message ?? error.localizedDescription
    }
    isSearching = true
  }

  public func clearSearch() {
    searchQuery = ""
    searchResults = []
    searchError = nil
    isSearching = false
  }

  public func remove(documentId: String) async {
    do {
      try await library.removeDocument(id: documentId)
      unavailableReasons[documentId] = nil
      renderedPages[documentId] = nil
      if selectedID == documentId { selectedID = nil }
      await refresh()
    } catch {
      alert = error.localizedDescription
    }
  }

  public func waitForImports() async {
    while !importTasks.isEmpty {
      let tasks = Array(importTasks.values)
      for task in tasks { await task.value }
    }
  }

  private func consumeImport(at url: URL) async {
    var eventDocumentId: String?
    let ocr = library.environment.config.ocr
    for await event in library.importEvents(at: url, runOCR: ocr.autoRunOnImport && ocr.isConfigured) {
      switch event {
      case .copied(let docId):
        eventDocumentId = docId
        selectedID = docId
        busyIDs.insert(docId)
        await refresh()
      case .rendered(let page, let total):
        if let id = eventDocumentId {
          renderedPages[id] = max(renderedPages[id] ?? 0, min(page, total))
          update(id) { $0.rendered = renderedPages[id] ?? 0 }
        }
      case .ocr(let progress):
        if let id = eventDocumentId {
          update(id) { $0.ocr = OCRCounts(done: progress.done, failed: progress.failed, pending: progress.pending) }
        }
      case .finished(let result):
        eventDocumentId = result.document.id
        selectedID = result.document.id
        busyIDs.remove(result.document.id)
        if result.alreadyImported { await refresh() }
        if result.ocr.status == .unavailable, let reason = result.ocr.reason {
          unavailableReasons[result.document.id] = reason
          await refresh()
        } else {
          unavailableReasons[result.document.id] = nil
          await refresh()
        }
      case .failed(let error):
        if let id = eventDocumentId { busyIDs.remove(id) }
        alert = error.message
      }
    }
    if let id = eventDocumentId, busyIDs.remove(id) != nil { await refresh() }
  }

  private func setBusy(_ documentId: String, _ busy: Bool) {
    if busy { busyIDs.insert(documentId) } else { busyIDs.remove(documentId) }
    update(documentId) { $0.isBusy = busy }
  }

  private func update(_ id: String, mutate: (inout LibraryRow) -> Void) {
    guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
    mutate(&rows[index])
  }
}
