import Foundation

extension SyncEngine {
  func syncDocuments(folder: URL, options: SyncConfig, pending: Set<String>, report: inout SyncReport) async {
    do {
      for (id, date) in try await library.store.pendingSyncDeletions() {
        do {
          try writeTombstone(id: id, date: date, folder: folder)
          try await library.store.setMeta("sync.deleted." + id, nil)
          report.documents.pushed += 1
        } catch { itemError(error, item: "delete \(id)", report: &report) }
      }
      let local = try await library.store.listDocuments(order: .importedDescending)
      let remote = try files.children(folder.appendingPathComponent("documents"))
      let ids = Set(local.map(\.id)).union(remote.map(\.lastPathComponent).filter { !$0.hasPrefix(".") })
      for id in ids.sorted() {
        try Task.checkCancellation()
        do { try await syncDocument(id: id, folder: folder, options: options, pending: pending, report: &report) } catch { itemError(error, item: "document \(id)", report: &report) }
      }
    } catch { itemError(error, item: "documents", report: &report) }
  }

  private func syncDocument(id: String, folder: URL, options: SyncConfig, pending: Set<String>, report: inout SyncReport) async throws {
    guard Self.safeID(id) else { throw StriaError.io("Invalid document directory") }
    let directory = folder.appendingPathComponent("documents/\(id)")
    let metadata = directory.appendingPathComponent("document.json")
    let original = directory.appendingPathComponent("original.pdf")
    let deleted = directory.appendingPathComponent("deleted.json")
    // A tombstone that has not downloaded must never be overwritten by a push.
    guard !pending.contains(deleted.path), !pending.contains(metadata.path) else { return }
    var local = try await library.store.document(id: id)
    if try files.exists(deleted) {
      let date = try files.read(SyncTombstone.self, at: deleted).deletedAt
      if let document = local, document.importedAt <= date {
        try await library.removeDocument(id: id, propagateSync: false)
        report.documents.pulled += 1
        return
      }
      guard let document = local, document.importedAt > date else { return }
      // A deliberate reimport after deletion resurrects this identity.
      try files.remove(deleted)
      try files.copy(library.paths.original(docId: id), to: original)
      try files.write(SyncDocument(document), at: metadata)
      report.documents.pushed += 1
    }
    let remote = try files.exists(metadata) ? files.read(SyncDocument.self, at: metadata) : nil
    if let remote {
      guard remote.docId == id, DocumentIdentity.docId(sha256Hex: remote.sha256) == id, remote.pageCount > 0 else {
        throw StriaError.io("Invalid document metadata")
      }
      if local == nil || local?.importStatus != .ready {
        guard !pending.contains(original.path), try files.exists(original) else { return }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("stria-sync-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: staging) }
        try files.copy(original, to: staging)
        guard try DocumentIdentity.sha256Hex(of: staging) == remote.sha256 else { throw StriaError.io("Sync PDF hash mismatch") }
        let imported = try await library.importDocument(at: staging, runOCR: false)
        guard imported.document.id == id, imported.document.pageCount == remote.pageCount else { throw StriaError.io("Sync PDF identity mismatch") }
        try await library.store.applySyncDocument(remote)
        local = try await library.store.document(id: id)
        report.documents.pulled += 1
      } else if let document = local, remote.updatedAt > document.updatedAt {
        guard document.sha256 == remote.sha256 else { throw StriaError.idCollision("Sync document hash mismatch") }
        try await library.store.applySyncDocument(remote)
        report.documents.pulled += 1
      } else if let document = local, document.updatedAt > remote.updatedAt {
        try files.write(SyncDocument(document), at: metadata)
        report.documents.pushed += 1
      }
    } else if let document = local, document.importStatus == .ready {
      guard !pending.contains(original.path) else { return }
      try files.copy(library.paths.original(docId: id), to: original)
      try files.write(SyncDocument(document), at: metadata)
      report.documents.pushed += 1
    }
    guard try await library.store.document(id: id)?.importStatus == .ready else { return }
    if options.ocr { await syncOCR(id: id, directory: directory, pending: pending, report: &report) }
    if options.summaries { await syncSummaries(id: id, directory: directory, pending: pending, report: &report) }
  }

  private func syncOCR(id: String, directory: URL, pending: Set<String>, report: inout SyncReport) async {
    do {
      for info in try await library.store.pageInfos(documentId: id) {
        let url = directory.appendingPathComponent("ocr/\(info.pageNumber).json")
        guard !pending.contains(url.path) else { continue }
        do {
          let remote = try files.exists(url) ? files.read(SyncOCR.self, at: url) : nil
          if let remote {
            guard remote.page == info.pageNumber, remote.status != .pending else { throw StriaError.io("Invalid OCR page") }
            if info.ocrUpdatedAt == nil || remote.updatedAt > info.ocrUpdatedAt ?? .distantPast {
              try await library.store.applySyncOCR(documentId: id, record: remote)
              report.ocr.pulled += 1
            } else if let value = SyncOCR(info), value.updatedAt > remote.updatedAt {
              try files.write(value, at: url); report.ocr.pushed += 1
            }
          } else if let value = SyncOCR(info) {
            try files.write(value, at: url); report.ocr.pushed += 1
          }
        } catch { itemError(error, item: "\(id) OCR \(info.pageNumber)", report: &report) }
      }
    } catch { itemError(error, item: "\(id) OCR", report: &report) }
  }

  private func syncSummaries(id: String, directory: URL, pending: Set<String>, report: inout SyncReport) async {
    do {
      let local = Dictionary(uniqueKeysWithValues: try await library.store.syncSummaries(documentId: id).map { ($0.record.pageNumber, $0) })
      for page in try await library.store.pageNumbers(documentId: id) {
        let url = directory.appendingPathComponent("summaries/\(page).json")
        guard !pending.contains(url.path) else { continue }
        do {
          let remote = try files.exists(url) ? files.read(SyncSummary.self, at: url) : nil
          if let remote {
            guard remote.record.documentId == id, remote.record.pageNumber == page else { throw StriaError.io("Invalid summary page") }
            if remote.record.updatedAt > local[page]?.record.updatedAt ?? .distantPast {
              try await library.store.applySyncSummary(remote); report.summaries.pulled += 1
            } else if let value = local[page], value.record.updatedAt > remote.record.updatedAt {
              try files.write(value, at: url); report.summaries.pushed += 1
            }
          } else if let value = local[page] {
            try files.write(value, at: url); report.summaries.pushed += 1
          }
        } catch { itemError(error, item: "\(id) summary \(page)", report: &report) }
      }
    } catch { itemError(error, item: "\(id) summaries", report: &report) }
  }
}
