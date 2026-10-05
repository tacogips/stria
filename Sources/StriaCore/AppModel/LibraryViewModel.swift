import CoreGraphics
import Foundation
import Observation

/// How the library shows its documents.
public enum LibraryViewMode: String, CaseIterable, Sendable {
  case list
  case card

  public static let storageKey = "libraryViewMode"

  public var title: String {
    switch self {
    case .list: "List"
    case .card: "Cards"
    }
  }
}

/// The OCR state of a whole document, for the library badge.
public enum DocumentOCRState: Equatable, Sendable {
  case notStarted
  case partial
  case complete
  case hasFailures
}

/// Which pages an OCR run from the app covers.
public enum OCRRange: Equatable, Sendable {
  /// Pages not OCRed yet or that failed.
  case remaining
  /// Every page; existing text is replaced.
  case all
  /// A page list such as "1-3, 8" (spaces allowed).
  case pages(String)

  public func selection(pageCount: Int) throws(StriaError) -> OCRSelection {
    switch self {
    case .remaining: return .pendingAndFailed
    case .all: return .pages(Array(1...max(pageCount, 1)))
    case .pages(let text):
      let compact = text.filter { !$0.isWhitespace }
      guard !compact.isEmpty else { throw .usage("Enter pages such as 1-3, 8") }
      return .pages(try PageListParser.parse(compact, pageCount: pageCount))
    }
  }
}

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
  /// Summary coverage (nil until loaded).
  public var summaries: PageSummaryCounts?
  /// The running summary run's progress, if any.
  public var summaryProgress: PageSummaryProgress?

  public var ocrState: DocumentOCRState {
    if ocr.failed > 0 { return .hasFailures }
    if ocr.done == 0 { return .notStarted }
    if ocr.pending > 0 { return .partial }
    return .complete
  }

  public init(id: String, title: String, pageCount: Int, importStatus: ImportStatus, rendered: Int,
              ocr: OCRCounts, unavailableReason: String? = nil, lastOpenedAt: Date? = nil, isBusy: Bool = false,
              summaries: PageSummaryCounts? = nil, summaryProgress: PageSummaryProgress? = nil) {
    self.id = id
    self.title = title
    self.pageCount = pageCount
    self.importStatus = importStatus
    self.rendered = rendered
    self.ocr = ocr
    self.unavailableReason = unavailableReason
    self.lastOpenedAt = lastOpenedAt
    self.isBusy = isBusy
    self.summaries = summaries
    self.summaryProgress = summaryProgress
  }
}

@MainActor
@Observable
public final class LibraryViewModel {
  public private(set) var rows: [LibraryRow] = []
  public var alert: String?
  public private(set) var isImporting = false
  public var selectedID: String?
  /// First-page thumbnails by document id, loaded on demand.
  public private(set) var thumbnails: [String: CGImage] = [:]
  public static let thumbnailMaxPixel = 320

  /// Progress of the page-summary run per document (absent when idle).
  public internal(set) var summaryProgress: [String: PageSummaryProgress] = [:]
  /// Bumped whenever a page summary may have changed, so views reload.
  public internal(set) var summaryRevision = 0
  /// Runs per document, chained so they never overlap (page order matters).
  var summaryTasks: [String: (id: UUID, task: Task<Void, Never>)] = [:]
  /// The outcome of each document's last finished summary run.
  public internal(set) var summaryReports: [String: PageSummaryRunReport] = [:]
  /// Runs waiting behind the running one, per document.
  public internal(set) var queuedSummaryRuns: [String: Int] = [:]
  /// Bumped by Cancel; queued runs from an older generation do not start.
  var summaryGenerations: [String: Int] = [:]
  /// The work of the running summary run per document (cancellable).
  var runningSummaryWork: [String: Task<PageSummaryRunResult, Error>] = [:]

  let library: StriaLibrary
  private var importTasks: [UUID: Task<Void, Never>] = [:]
  private var unavailableReasons: [String: String] = [:]
  private var renderedPages: [String: Int] = [:]
  private var busyIDs: Set<String> = []
  private var thumbnailLoads: Set<String> = []

  public init(library: StriaLibrary) {
    self.library = library
  }

  public func refresh() async {
    do {
      let summaryCounts = (try? await library.pageSummaryCounts()) ?? [:]
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
          isBusy: busyIDs.contains(summary.id),
          summaries: summaryCounts[summary.id],
          summaryProgress: summaryProgress[summary.id]
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
      startAutoSummary(documentId: documentId, pages: summary.processed)
    } catch {
      alert = error.localizedDescription
    }
  }

  /// Whether OCR and the agent have a vendor; the library banner points to
  /// Settings while either is missing.
  public var ocrConfigured: Bool { library.environment.config.ocr.isConfigured }
  public var agentConfigured: Bool { library.environment.config.agent.isConfigured }
  public var ocrRunsAutomatically: Bool { library.environment.config.ocr.autoRunOnImport }

  /// Loads the first-page thumbnail once; a document still rendering is
  /// retried when its row refreshes as ready.
  public func loadThumbnail(documentId: String) async {
    guard thumbnails[documentId] == nil, !thumbnailLoads.contains(documentId) else { return }
    thumbnailLoads.insert(documentId)
    defer { thumbnailLoads.remove(documentId) }
    if let image = try? await library.firstPageThumbnail(documentId: documentId, maxPixel: Self.thumbnailMaxPixel) {
      thumbnails[documentId] = image
    }
  }

  /// OCR every page again, whatever its state (done pages are replaced).
  public func rerunOCRAllPages(documentId: String) async {
    await runOCR(documentId: documentId, range: .all)
  }

  /// Runs OCR on the chosen pages; pages already OCRed in a chosen range or
  /// in `.all` are replaced. An invalid page list sets `alert`.
  public func runOCR(documentId: String, range: OCRRange) async {
    guard let row = rows.first(where: { $0.id == documentId }), row.pageCount > 0 else { return }
    let selection: OCRSelection
    do {
      selection = try range.selection(pageCount: row.pageCount)
    } catch {
      alert = error.message
      return
    }
    setBusy(documentId, true)
    defer { setBusy(documentId, false) }
    do {
      let summary = try await library.runOCR(documentId: documentId, selection: selection)
      unavailableReasons[documentId] = summary.unavailableReason
      await refresh()
      startAutoSummary(documentId: documentId, pages: summary.processed)
    } catch {
      alert = (error as? StriaError)?.message ?? error.localizedDescription
    }
  }

  public func remove(documentId: String) async {
    do {
      try await library.removeDocument(id: documentId)
      unavailableReasons[documentId] = nil
      renderedPages[documentId] = nil
      thumbnails[documentId] = nil
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
          if result.ocr.done > 0 { startAutoSummary(documentId: result.document.id, pages: nil) }
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

  func update(_ id: String, mutate: (inout LibraryRow) -> Void) {
    guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
    mutate(&rows[index])
  }
}
