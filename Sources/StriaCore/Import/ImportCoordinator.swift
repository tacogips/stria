import Foundation
import PDFKit

struct ImportCoordinator: Sendable {
  let library: StriaLibrary

  func run(url: URL, runOCR: Bool, continuation: AsyncStream<ImportEvent>.Continuation) async {
    do {
      let result = try await perform(url: url, runOCR: runOCR, continuation: continuation)
      continuation.yield(.finished(result))
    } catch is CancellationError {
      continuation.finish()
    } catch let error as StriaError {
      continuation.yield(.failed(error))
    } catch {
      continuation.yield(.failed(.io("Import failed: \(error.localizedDescription)")))
    }
    continuation.finish()
  }

  private func perform(url: URL, runOCR: Bool, continuation: AsyncStream<ImportEvent>.Continuation) async throws -> ImportResult {
    // Hash before opening with PDFKit: re-importing an existing file then
    // costs one read, not a full document open.
    let sha256 = try DocumentIdentity.sha256Hex(of: url)
    let docId = DocumentIdentity.docId(sha256Hex: sha256)
    if let existing = try await library.store.document(sha256: sha256) {
      return try await resume(existing, source: url, runOCR: runOCR, continuation: continuation)
    }
    let inspection = try PDFInspector.inspect(url: url)

    if let sameId = try await library.store.document(id: docId) {
      // A concurrent importer of the same bytes may have inserted the row since the lookup above.
      guard sameId.sha256 == sha256 else {
        throw StriaError.idCollision("Document id \(docId) already exists with different content")
      }
      return try await resume(sameId, source: url, runOCR: runOCR, continuation: continuation)
    }

    let original = library.paths.original(docId: docId)
    try copyOriginalAtomically(from: url, to: original)
    let attributes = try FileManager.default.attributesOfItem(atPath: original.path)
    let byteSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    let now = library.environment.clock()
    let config = library.environment.config
    let record = DocumentRecord(
      id: docId, sha256: sha256, title: inspection.title, originalFilename: url.lastPathComponent,
      originalPath: "originals/\(docId).pdf", byteSize: byteSize, pageCount: inspection.pageCount,
      importStatus: .rendering, renderDPI: config.render.dpi, imageFormat: config.render.imageFormat,
      ocrVendor: config.ocr.vendor, ocrModel: config.ocr.model, importedAt: now, updatedAt: now
    )
    do {
      try await library.store.insertDocument(record)
    } catch {
      // A concurrent importer of the same bytes may have inserted the row
      // between our lookup and this insert: join its import instead of failing.
      if let existing = try await library.store.document(sha256: sha256) {
        return try await resume(existing, source: url, runOCR: runOCR, continuation: continuation)
      }
      try? FileManager.default.removeItem(at: original)
      throw error
    }
    continuation.yield(.copied(docId: docId))
    try await renderMissingPages(url: original, document: record, continuation: continuation)
    return try await finish(documentId: docId, alreadyImported: false, runOCR: runOCR, continuation: continuation)
  }

  /// Re-import of known bytes: restores a missing original, resumes an
  /// interrupted render, and never re-renders or re-OCRs finished work.
  private func resume(_ existing: DocumentRecord, source: URL, runOCR: Bool,
                      continuation: AsyncStream<ImportEvent>.Continuation) async throws -> ImportResult {
    try ensureOriginal(at: library.paths.original(docId: existing.id), source: source)
    if existing.importStatus == .ready {
      let counts = try await library.store.ocrCounts(documentId: existing.id)
      let summary = try await library.summary(of: existing)
      return ImportResult(alreadyImported: true, document: summary,
                          ocr: ImportOCROutcome(status: .skipped, reason: nil, done: counts.done, failed: counts.failed, pending: counts.pending))
    }
    continuation.yield(.copied(docId: existing.id))
    try await renderMissingPages(url: library.paths.original(docId: existing.id), document: existing, continuation: continuation)
    return try await finish(documentId: existing.id, alreadyImported: true, runOCR: runOCR, continuation: continuation)
  }

  private func ensureOriginal(at destination: URL, source: URL) throws {
    guard !FileManager.default.fileExists(atPath: destination.path) else { return }
    try copyOriginalAtomically(from: source, to: destination)
  }

  private func copyOriginalAtomically(from source: URL, to destination: URL) throws {
    do {
      try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
      let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
      defer { try? FileManager.default.removeItem(at: temporary) }
      try FileManager.default.copyItem(at: source, to: temporary)
      do {
        try FileManager.default.moveItem(at: temporary, to: destination)
      } catch {
        // A concurrent importer of the same bytes won the rename; its copy is byte-identical.
        guard FileManager.default.fileExists(atPath: destination.path) else { throw error }
      }
    } catch {
      throw StriaError.io("Could not copy original PDF: \(error.localizedDescription)")
    }
  }

  private func renderMissingPages(url: URL, document: DocumentRecord,
                                  continuation: AsyncStream<ImportEvent>.Continuation) async throws {
    guard let pdf = PDFDocument(url: url) else { throw StriaError.invalidPDF("Could not open original PDF") }
    let existing = Set(try await library.store.pageNumbers(documentId: document.id))
    // A resumed import renders with the DPI and format recorded on the row,
    // not the current config, so every page of a document matches its row.
    let config = library.environment.config.render
    for pageNumber in 1...document.pageCount {
      try Task.checkCancellation()
      guard !existing.contains(pageNumber) else { continue }
      guard let page = pdf.page(at: pageNumber - 1) else { throw StriaError.invalidPDF("PDF page \(pageNumber) is unavailable") }
      let stored = try autoreleasepool {
        let image = try PageRenderer.render(page: page, dpi: document.renderDPI, maxPixelDimension: config.maxPixelDimension)
        return try ImageCodec.encode(image, preferred: document.imageFormat, quality: config.quality)
      }
      try await library.store.insertPage(documentId: document.id, pageNumber: pageNumber, image: stored)
      continuation.yield(.rendered(page: pageNumber, total: document.pageCount))
    }
    let outline = OutlineExtractor.encodeJSON(OutlineExtractor.extract(from: pdf))
    try await library.store.markDocumentReady(id: document.id, outlineJSON: outline)
  }

  private func finish(documentId: String, alreadyImported: Bool, runOCR: Bool,
                      continuation: AsyncStream<ImportEvent>.Continuation) async throws -> ImportResult {
    let record = try await library.document(id: documentId)
    let outcome: ImportOCROutcome
    if runOCR {
      let summary = try await OCRCoordinator(library: library).run(documentId: documentId, selection: .pending) {
        continuation.yield(.ocr($0))
      }
      let status: ImportOCRStatus = summary.unavailableReason != nil ? .unavailable : (summary.failed > 0 ? .partial : .completed)
      outcome = ImportOCROutcome(status: status, reason: summary.unavailableReason, done: summary.done, failed: summary.failed, pending: summary.pending)
    } else {
      let counts = try await library.store.ocrCounts(documentId: documentId)
      outcome = ImportOCROutcome(status: .skipped, reason: nil, done: counts.done, failed: counts.failed, pending: counts.pending)
    }
    return ImportResult(alreadyImported: alreadyImported, document: try await library.summary(of: record), ocr: outcome)
  }
}
