import Foundation
@testable import StriaCore
import Testing

@Suite struct SyncMergeTests {
  @Test func failedOCRAndNewerSummaryPreserveRemoteTimestamps() async throws {
    try await withTestDataRoot { paths in
      let f = try SyncFixture.make(paths)
      let id = try await f.a.importDocument(at: f.source, runOCR: true).document.id
      _ = try await f.a.summarizePages(documentId: id, request: .init(selection: .missing))
      _ = try await SyncEngine(library: f.a).sync()
      _ = try await SyncEngine(library: f.b).sync()
      await f.ocrB.script(docId: id, page: 1, .failure(.failed("recognition failed")))
      _ = try await f.b.runOCR(documentId: id, selection: .pages([1]))
      await f.agent.enqueue(.success("New summary on B"))
      _ = try await f.b.summarizePages(documentId: id, request: .init(selection: .pages([2]), ocrFirst: false))
      let pushed = try await SyncEngine(library: f.b).sync()
      #expect(pushed.ocr.pushed == 1 && pushed.summaries.pushed == 1 && pushed.errors.isEmpty)
      let pulled = try await SyncEngine(library: f.a).sync()
      #expect(pulled.ocr.pulled == 1 && pulled.summaries.pulled == 1 && pulled.errors.isEmpty)
      let page = try await f.a.pageText(documentId: id, page: 1)
      #expect(page.ocrStatus == .failed && page.ocrText == nil && page.ocrError == "recognition failed")
      #expect(page.ocrUpdatedAt == Date(timeIntervalSince1970: 2000))
      #expect(try await f.a.search(query: "text").results.map(\.page) == [2])
      let summary = try await f.a.pageSummary(documentId: id, page: 2)
      #expect(summary?.summary == "New summary on B" && summary?.isStale == false)
      #expect(summary?.updatedAt == Date(timeIntervalSince1970: 2000))
      #expect(try await SyncEngine(library: f.a).sync() == SyncReport(folder: f.folder.path))
    }
  }

  @Test func libraryChatsSyncWhilePDFsAreDisabled() async throws {
    try await withTestDataRoot { paths in
      let f = try SyncFixture.make(paths)
      let id = try await f.a.importDocument(at: f.source, runOCR: true).document.id
      // Library retrieval uses OCR; its thread has no anchor document.
      let answer = try await f.a.ask(.init(question: "text", context: .library))
      _ = try await f.a.ask(.init(question: "page", context: .page(docId: id, page: 1)))
      let chatsOnly = SyncConfig(documents: false)
      let push = try await SyncEngine(library: f.a).sync(options: chatsOnly)
      #expect(push.chats.pushed == 1 && push.documents == SyncCounts() && push.errors.isEmpty)
      let pull = try await SyncEngine(library: f.b).sync(options: chatsOnly)
      #expect(pull.chats.pulled == 1 && pull.documents == SyncCounts() && pull.errors.isEmpty)
      #expect(try await f.b.threadMessages(threadId: answer.threadId).count == 2)
      #expect(try await f.b.store.listDocuments(order: .recents).isEmpty)
      #expect(try await SyncEngine(library: f.b).sync(options: chatsOnly) == SyncReport(folder: f.folder.path))
    }
  }

  @Test func disabledPageKindsAreNotPublished() async throws {
    try await withTestDataRoot { paths in
      let f = try SyncFixture.make(paths)
      let id = try await f.a.importDocument(at: f.source, runOCR: true).document.id
      _ = try await f.a.summarizePages(documentId: id, request: .init(selection: .missing))
      _ = try await f.a.ask(.init(question: "page", context: .page(docId: id, page: 1)))
      let report = try await SyncEngine(library: f.a).sync(options: .init(ocr: false, summaries: false, chats: false))
      #expect(report.documents.pushed == 1 && report.ocr == SyncCounts() && report.summaries == SyncCounts() && report.chats == SyncCounts())
      for name in ["documents/\(id)/ocr", "documents/\(id)/summaries", "chats"] {
        #expect(!FileManager.default.fileExists(atPath: f.folder.appendingPathComponent(name).path))
      }
    }
  }

  @Test func formatPlaceholderBlocksEntirePass() async throws {
    try await withTestDataRoot { paths in
      let f = try SyncFixture.make(paths)
      _ = try await f.a.importDocument(at: f.source, runOCR: true)
      try FileManager.default.createDirectory(at: f.folder, withIntermediateDirectories: true)
      try Data().write(to: f.folder.appendingPathComponent(".format.json.icloud"))
      let report = try await SyncEngine(library: f.a, download: { _ in }).sync()
      #expect(report.pending == 1 && report.documents == SyncCounts() && report.errors.isEmpty)
      #expect(!FileManager.default.fileExists(atPath: f.folder.appendingPathComponent("format.json").path))
    }
  }
}
