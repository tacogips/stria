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

  public init(id: String, title: String, pageCount: Int, importStatus: ImportStatus, rendered: Int,
              ocr: OCRCounts, unavailableReason: String? = nil, lastOpenedAt: Date? = nil) {
    self.id = id
    self.title = title
    self.pageCount = pageCount
    self.importStatus = importStatus
    self.rendered = rendered
    self.ocr = ocr
    self.unavailableReason = unavailableReason
    self.lastOpenedAt = lastOpenedAt
  }
}

@MainActor
@Observable
public final class LibraryViewModel {
  public private(set) var rows: [LibraryRow] = []
  public var alert: String?
  public private(set) var isImporting = false
  public var selectedID: String?

  private let library: StriaLibrary
  private var importTasks: [UUID: Task<Void, Never>] = [:]
  private var unavailableReasons: [String: String] = [:]
  private var renderedPages: [String: Int] = [:]

  public init(library: StriaLibrary) {
    self.library = library
  }

  public func refresh() async {
    do {
      let summaries = try await library.listDocuments(order: .recents)
      var refreshedRows: [LibraryRow] = []
      for summary in summaries {
        let record = try await library.document(id: summary.id)
        refreshedRows.append(LibraryRow(
          id: summary.id,
          title: summary.title,
          pageCount: summary.pageCount,
          importStatus: summary.importStatus,
          rendered: renderedPages[summary.id] ?? (summary.importStatus == .ready ? summary.pageCount : 0),
          ocr: summary.ocr,
          unavailableReason: unavailableReasons[summary.id],
          lastOpenedAt: record.lastOpenedAt
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

  public func waitForImports() async {
    while !importTasks.isEmpty {
      let tasks = Array(importTasks.values)
      for task in tasks { await task.value }
    }
  }

  private func consumeImport(at url: URL) async {
    var eventDocumentId: String?
    for await event in library.importEvents(at: url, runOCR: true) {
      switch event {
      case .copied(let docId):
        eventDocumentId = docId
        selectedID = docId
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
        if result.alreadyImported { await refresh() }
        if result.ocr.status == .unavailable, let reason = result.ocr.reason {
          unavailableReasons[result.document.id] = reason
          await refresh()
        } else {
          unavailableReasons[result.document.id] = nil
          await refresh()
        }
      case .failed(let error):
        alert = error.message
      }
    }
  }

  private func update(_ id: String, mutate: (inout LibraryRow) -> Void) {
    guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
    mutate(&rows[index])
  }
}
