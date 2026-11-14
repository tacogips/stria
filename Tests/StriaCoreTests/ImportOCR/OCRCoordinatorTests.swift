import Foundation
import StriaCore
import Testing

@Suite("OCRCoordinatorTests") struct OCRCoordinatorTests {
  @Test func selectionsRetryFailuresAndAllowExplicitReruns() async throws {
    try await withTestDataRoot { paths in
      let fake = FakeOCRService()
      let (library, source) = try await makeImportFixture(paths: paths, pageTexts: ["a", "b", "c"], ocr: fake)
      let imported = try await importFixture(library, source: source)
      let id = imported.document.id
      await fake.script(docId: id, page: 2, .failure(.failed("temporary")))
      let first = try await library.runOCR(documentId: id, selection: .pending)
      #expect(first.processed == [1, 2, 3])
      #expect(first.failed == 1)
      #expect(try await library.store.pageInfo(documentId: id, page: 2)?.ocrStatus == .failed)
      let pendingAgain = try await library.runOCR(documentId: id, selection: .pending)
      #expect(pendingAgain.processed.isEmpty)
      await fake.script(docId: id, page: 2, .success("recovered"))
      let retry = try await library.runOCR(documentId: id, selection: .pendingAndFailed)
      #expect(retry.processed == [2])
      #expect(retry.failed == 0)
      let rerun = try await library.runOCR(documentId: id, selection: .pages([2]))
      #expect(rerun.processed == [2])
      #expect(try await library.store.pageInfo(documentId: id, page: 2)?.ocrAttempts == 1)
      #expect(try await library.store.agentRuns(documentId: id).count == 5)
    }
  }

  @Test func concurrencyIsBoundedAndEveryCallHasOneRunAndJSONLLine() async throws {
    try await withTestDataRoot { paths in
      let fake = FakeOCRService()
      await fake.setDelay(nanoseconds: 30_000_000)
      let (library, source) = try await makeImportFixture(paths: paths, pageTexts: (1...6).map(String.init), ocr: fake)
      let imported = try await importFixture(library, source: source)
      let summary = try await library.runOCR(documentId: imported.document.id, selection: .pending)
      #expect(summary.processed == [1, 2, 3, 4, 5, 6])
      #expect(await fake.maxInFlight == 2)
      let runs = try await library.store.agentRuns(documentId: imported.document.id)
      #expect(runs.count == 6)
      #expect(runs.allSatisfy { $0.kind == .ocr })
      let logFiles = try FileManager.default.contentsOfDirectory(at: paths.logs, includingPropertiesForKeys: nil)
      let lines = try logFiles.flatMap { try String(contentsOf: $0, encoding: .utf8).split(whereSeparator: \.isNewline) }
      #expect(lines.count == 6)
    }
  }

  @Test func unavailableDoesNotTouchPagesOrWriteRunsAndFencesAreCleaned() async throws {
    try await withTestDataRoot { paths in
      let fake = FakeOCRService()
      let (library, source) = try await makeImportFixture(paths: paths, pageTexts: ["a", "b"], ocr: fake)
      let imported = try await importFixture(library, source: source)
      await fake.setDefault(.failure(.unavailable("vendor is not configured")))
      let unavailable = try await library.runOCR(documentId: imported.document.id, selection: .pending)
      #expect(unavailable.unavailableReason == "vendor is not configured")
      #expect(unavailable.processed.isEmpty)
      #expect(unavailable.pending == 2)
      #expect(try await library.store.agentRuns(documentId: imported.document.id).isEmpty)

      await fake.setDefault(.success("```\nhello\n```"))
      let done = try await library.runOCR(documentId: imported.document.id, selection: .pages([1]))
      #expect(done.done == 1)
      #expect(try await library.store.pageInfo(documentId: imported.document.id, page: 1)?.ocrText == "hello")
    }
  }

  @Test func errorTruncationAndRunLogFailureAreTolerated() async throws {
    try await withTestDataRoot { paths in
      let fake = FakeOCRService()
      let marker = paths.root.appendingPathComponent("run-log-failure.txt")
      let (library, source) = try await makeImportFixture(paths: paths, pageTexts: ["only"], ocr: fake,
        onRunLogFailure: { _ in try? Data("called".utf8).write(to: marker) })
      let imported = try await importFixture(library, source: source)
      try FileManager.default.removeItem(at: paths.logs)
      try Data("file blocks logs".utf8).write(to: paths.logs)
      let longError = String(repeating: "e", count: 3000)
      await fake.setDefault(.failure(.failed(longError)))
      let result = try await library.runOCR(documentId: imported.document.id, selection: .pending)
      #expect(result.failed == 1)
      #expect(try await library.store.pageInfo(documentId: imported.document.id, page: 1)?.ocrError?.count == 2000)
      #expect(FileManager.default.fileExists(atPath: marker.path))
      #expect(try await library.store.agentRuns(documentId: imported.document.id).count == 1)
    }
  }
}
