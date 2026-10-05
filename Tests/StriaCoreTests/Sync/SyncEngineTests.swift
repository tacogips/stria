import Foundation
@testable import StriaCore
import Testing

@Suite struct SyncEngineTests {
  @Test(arguments: [false, true]) func twoDevicesRoundTripWithoutTimestampBounce(forceLike: Bool) async throws {
    try await withTestDataRoot { paths in
      let f = try SyncFixture.make(paths, forceLike: forceLike)
      await f.ocrA.setDefault(.success(#"{"body":"searchable otter", "tags":["wildlife"]}"#))
      let imported = try await f.a.importDocument(at: f.source, runOCR: true)
      let id = imported.document.id
      await f.agent.enqueue(.success("Otters swim.")); await f.agent.enqueue(.success("Second summary."))
      _ = try await f.a.summarizePages(documentId: id, request: .init(selection: .missing))
      let answer = try await f.a.ask(.init(question: "What is here?", context: .page(docId: id, page: 1)))
      try await f.a.store.setThreadTitle(threadId: answer.threadId, title: "Otters")
      let messages = try await f.a.threadMessages(threadId: answer.threadId)
      try await f.a.store.setThreadSummary(threadId: answer.threadId, summary: "Conversation", throughMessageId: #require(messages.last).id)
      let a = SyncEngine(library: f.a), b = SyncEngine(library: f.b)
      let pushed = try await a.sync()
      #expect(pushed.errors.isEmpty)
      #expect(pushed.documents.pushed == 1 && pushed.ocr.pushed == 2 && pushed.summaries.pushed == 2 && pushed.chats.pushed == 1)
      let pulled = try await b.sync()
      #expect(pulled.errors.isEmpty)
      #expect(pulled.documents.pulled == 1 && pulled.ocr.pulled == 2 && pulled.summaries.pulled == 2 && pulled.chats.pulled == 1)
      #expect(try await f.b.store.pageImage(documentId: id, page: 1) != nil)
      #expect(try await f.b.pageText(documentId: id, page: 1).ocrTags == ["wildlife"])
      #expect(try await f.b.search(query: "otter").results.count == 2)
      #expect(try await f.b.search(query: "wildlife").results.isEmpty)
      #expect(try await f.b.pageSummary(documentId: id, page: 1)?.isStale == false)
      #expect(try await f.b.threadOverview(threadId: answer.threadId)?.title == "Otters")
      #expect(try await f.b.threadOverview(threadId: answer.threadId)?.isSummaryCurrent == true)
      #expect(try await f.b.threadMessages(threadId: answer.threadId).map(\.content) == messages.map(\.content))
      #expect(await f.ocrB.requests.isEmpty)
      await f.ocrB.setDefault(.success("newer beaver"))
      _ = try await f.b.runOCR(documentId: id, selection: .pages([1]))
      #expect(try await b.sync().ocr.pushed == 1)
      #expect(try await a.sync().ocr.pulled == 1)
      #expect(try await f.a.pageText(documentId: id, page: 1).ocrText == "newer beaver")
      #expect(try await f.a.pageSummary(documentId: id, page: 1)?.isStale == true)
      #expect(try await a.sync() == SyncReport(folder: f.folder.path))
      #expect(try await b.sync() == SyncReport(folder: f.folder.path))
      // A newer thread replaces messages and maps summary coverage to new ids.
      _ = try await f.b.ask(.init(question: "More?", context: .page(docId: id, page: 1), threadId: answer.threadId))
      try await f.b.store.setThreadTitle(threadId: answer.threadId, title: "Beavers")
      #expect(try await b.sync().chats.pushed == 1)
      #expect(try await a.sync().chats.pulled == 1)
      #expect(try await f.a.threadMessages(threadId: answer.threadId).count == 4)
      #expect(try await f.a.threadOverview(threadId: answer.threadId)?.isSummaryCurrent == false)
    }
  }

  @Test func tombstonesPropagateAndDoNotResurrect() async throws {
    try await withTestDataRoot { paths in
      let f = try SyncFixture.make(paths)
      let id = try await f.a.importDocument(at: f.source, runOCR: true).document.id
      _ = try await SyncEngine(library: f.a).sync()
      _ = try await SyncEngine(library: f.b).sync()
      try await f.b.removeDocument(id: id)
      #expect(FileManager.default.fileExists(atPath: f.folder.appendingPathComponent("documents/\(id)/deleted.json").path))
      #expect(!FileManager.default.fileExists(atPath: f.folder.appendingPathComponent("documents/\(id)/original.pdf").path))
      #expect(try await SyncEngine(library: f.a).sync().documents.pulled == 1)
      #expect(try await f.a.store.document(id: id) == nil)
      #expect(try await SyncEngine(library: f.a).sync() == SyncReport(folder: f.folder.path))
    }
  }

  @Test func pendingTombstoneIsDurableWhileFolderUnavailable() async throws {
    try await withTestDataRoot { paths in
      let f = try SyncFixture.make(paths)
      let id = try await f.a.importDocument(at: f.source, runOCR: false).document.id
      _ = try await SyncEngine(library: f.a).sync()
      let missing = StriaEnvironment(paths: f.a.paths, config: f.a.environment.config, ocrService: f.ocrA, agentService: f.agent,
                                     clock: { Date(timeIntervalSince1970: 3000) },
                                     syncFolder: SyncFolder(environment: [:], homeDirectory: paths.root, platform: .iOS), syncFileCoordinator: LocalSyncFileCoordinator())
      let reopened = try StriaLibrary.open(environment: missing)
      try await reopened.removeDocument(id: id)
      #expect(try await reopened.store.pendingSyncDeletions()[id] != nil)
      let report = try await SyncEngine(library: reopened).sync(folder: f.folder)
      #expect(report.errors.isEmpty && report.documents.pushed == 1)
      #expect(try await reopened.store.pendingSyncDeletions().isEmpty)
    }
  }

  @Test func disabledKindsNeitherPushNorPull() async throws {
    try await withTestDataRoot { paths in
      let f = try SyncFixture.make(paths)
      let id = try await f.a.importDocument(at: f.source, runOCR: true).document.id
      _ = try await f.a.summarizePages(documentId: id, request: .init(selection: .missing))
      _ = try await f.a.ask(.init(question: "q", context: .page(docId: id, page: 1)))
      let off = SyncConfig(documents: false, ocr: true, summaries: true, chats: false)
      #expect(try await SyncEngine(library: f.a).sync(options: off) == SyncReport(folder: f.folder.path))
      _ = try await SyncEngine(library: f.a).sync()
      #expect(try await SyncEngine(library: f.b).sync(options: off) == SyncReport(folder: f.folder.path))
      #expect(try await f.b.store.document(id: id) == nil)
      let pdfOnly = SyncConfig(ocr: false, summaries: false, chats: false)
      let report = try await SyncEngine(library: f.b).sync(options: pdfOnly)
      #expect(report.documents.pulled == 1 && report.ocr == SyncCounts() && report.summaries == SyncCounts() && report.chats == SyncCounts())
      #expect(try await f.b.pageText(documentId: id, page: 1).ocrStatus == .pending)
      #expect(try await f.b.pageSummary(documentId: id, page: 1) == nil)
      #expect(try await f.b.store.syncThreads().isEmpty)
    }
  }

  @Test func newerFormatRefusedBeforeChangesAndPlaceholderSkipped() async throws {
    try await withTestDataRoot { paths in
      let f = try SyncFixture.make(paths)
      let id = try await f.a.importDocument(at: f.source, runOCR: false).document.id
      try FileManager.default.createDirectory(at: f.folder, withIntermediateDirectories: true)
      let format = f.folder.appendingPathComponent("format.json")
      let data = Data(#"{"version":2}"#.utf8)
      try data.write(to: format)
      await #expect(throws: StriaError.self) { try await SyncEngine(library: f.a).sync() }
      #expect(try Data(contentsOf: format) == data)
      #expect(try FileManager.default.contentsOfDirectory(atPath: f.folder.path) == ["format.json"])
      try Data(#"{"version":1}"#.utf8).write(to: format)
      let directory = f.folder.appendingPathComponent("documents/\(id)")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let placeholder = directory.appendingPathComponent(".document.json.icloud")
      try Data().write(to: placeholder)
      let engine = SyncEngine(library: f.a, download: { url in #expect(url.resolvingSymlinksInPath() == placeholder.resolvingSymlinksInPath()) })
      let report = try await engine.sync()
      #expect(report.pending == 1 && report.documents == SyncCounts() && report.errors.isEmpty)
      #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("document.json").path))
    }
  }

  @Test func corruptPageDoesNotStopOtherItems() async throws {
    try await withTestDataRoot { paths in
      let f = try SyncFixture.make(paths)
      let id = try await f.a.importDocument(at: f.source, runOCR: true).document.id
      _ = try await SyncEngine(library: f.a).sync()
      let corrupt = f.folder.appendingPathComponent("documents/\(id)/ocr/1.json")
      try Data("bad json".utf8).write(to: corrupt)
      let report = try await SyncEngine(library: f.b).sync()
      #expect(report.errors.count == 1 && report.documents.pulled == 1 && report.ocr.pulled == 1)
      #expect(try await f.b.pageText(documentId: id, page: 2).ocrStatus == .done)
    }
  }
}
