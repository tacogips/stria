import Foundation
@testable import StriaCore
import Testing

/// A clock that advances one second per reading, so OCR timestamps differ.
final class TickingClock: @unchecked Sendable {
  private let lock = NSLock()
  private var current = Date(timeIntervalSince1970: 1_800_000_000)
  func now() -> Date {
    lock.lock(); defer { lock.unlock() }
    current = current.addingTimeInterval(1)
    return current
  }
}

private func summaryConfig(language: String = "Japanese", prompt: String? = nil, auto: Bool = false) -> StriaConfig {
  var config = StriaConfig.testing
  config.ocr.autoRunOnImport = true
  config.summary = .init(vendor: "claude-code", model: "summary-model", prompt: prompt, language: language, autoRunAfterOCR: auto)
  return config
}

@Suite @MainActor struct PageSummaryTests {
  @Test func pagesAreSummarizedInOrderWithThePreviousPageAsContext() async throws {
    try await withAppModelDataRoot { paths in
      let agent = FakeAgentService()
      let clock = TickingClock()
      let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one", "two", "three"], agent: agent,
                                                      config: summaryConfig(), clock: clock.now)
      let id = try await library.importDocument(at: source, runOCR: true).document.id
      for answer in ["- page one points", "- page two points", "- page three points"] { await agent.enqueue(.success(answer)) }

      let result = try await library.summarizePages(documentId: id, request: PageSummaryRequest(selection: .missing))
      #expect(result.summarized == [1, 2, 3])
      #expect(result.unavailableReason == nil)
      let requests = await agent.requests
      #expect(requests.count == 3)
      #expect(requests[0].systemPrompt.contains("Write the summary in Japanese."))
      #expect(!requests[0].systemPrompt.contains("{language}"))
      #expect(requests[0].contextPages.isEmpty)
      #expect(requests[0].settings.vendor == "claude-code")
      #expect(requests[0].settings.model == "summary-model")
      #expect(requests[0].question.contains("<target_page page=\"1\">\ntext \(id) p1"))
      #expect(!requests[0].question.contains("previous_page"))
      #expect(requests[1].question.contains("<previous_page page=\"1\">"))
      #expect(requests[1].question.contains("text \(id) p1"))
      #expect(requests[1].question.contains("<summary>\n- page one points\n</summary>"))
      #expect(requests[2].question.contains("<summary>\n- page two points\n</summary>"))

      let second = try #require(try await library.pageSummary(documentId: id, page: 2))
      #expect(second.summary == "- page two points")
      #expect(second.status == .done)
      #expect(second.language == "Japanese")
      #expect(!second.isStale)
      // Summaries are not searchable.
      #expect(try await library.search(query: "points").results.isEmpty)
      #expect(try await library.pagesNeedingSummary(documentId: id).isEmpty)

      // OCR again makes that page's summary stale.
      _ = try await library.runOCR(documentId: id, selection: .pages([2]))
      #expect(try await library.pageSummary(documentId: id, page: 2)?.isStale == true)
      #expect(try await library.pagesNeedingSummary(documentId: id) == [2])

      // A redo with instructions and another language.
      await agent.enqueue(.success("Numbers on page two."))
      _ = try await library.summarizePages(documentId: id, request: PageSummaryRequest(
        selection: .pages([2]), instruction: "  Focus on numbers  ", language: "English"))
      let redo = try #require(await agent.requests.last)
      #expect(redo.systemPrompt.contains("Write the summary in English."))
      #expect(redo.question.contains("Additional instructions for this summary:\nFocus on numbers"))
      let redone = try #require(try await library.pageSummary(documentId: id, page: 2))
      #expect(redone.summary == "Numbers on page two.")
      #expect(redone.instruction == "Focus on numbers")
      #expect(redone.language == "English")
      #expect(!redone.isStale)

      // A failure keeps the previous summary and records the error.
      await agent.enqueue(.failure(.failed("boom")))
      let failed = try await library.summarizePages(documentId: id, request: PageSummaryRequest(selection: .pages([1])))
      #expect(failed.failures.map(\.page) == [1])
      let first = try #require(try await library.pageSummary(documentId: id, page: 1))
      #expect(first.status == .failed)
      #expect(first.error == "boom")
      #expect(first.summary == "- page one points")
      #expect(try await library.pagesNeedingSummary(documentId: id) == [1])
    }
  }

  @Test func blankPagesSkipTheModelAndUnOCRedPagesAreSkipped() async throws {
    try await withAppModelDataRoot { paths in
      let agent = FakeAgentService()
      let ocr = FakeOCRService()
      var config = summaryConfig(language: PageSummaryLanguage.auto, prompt: "Summarize in {language}.")
      config.ocr.autoRunOnImport = false
      let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one", "two", "three"], ocr: ocr,
                                                      agent: agent, config: config)
      let id = try await library.importDocument(at: source, runOCR: false).document.id
      await ocr.script(docId: id, page: 2, .success(""))
      _ = try await library.runOCR(documentId: id, selection: .pages([1, 2]))
      let result = try await library.summarizePages(
        documentId: id, request: PageSummaryRequest(selection: .pages([1, 2, 3]), ocrFirst: false))
      #expect(result.summarized == [1, 2])
      #expect(result.skipped == [3])
      #expect(result.ocred.isEmpty)
      let requests = await agent.requests
      #expect(requests.count == 1)
      #expect(requests.first?.systemPrompt == "Summarize in the same language as the target page's text.")
      #expect(try await library.pageSummary(documentId: id, page: 2)?.summary == "")
      #expect(try await library.pageSummary(documentId: id, page: 3) == nil)
      await #expect(throws: StriaError.self) {
        try await library.summarizePages(documentId: id, request: PageSummaryRequest(selection: .pages([9])))
      }
    }
  }

  @Test func withoutAVendorNothingIsCalled() async throws {
    try await withAppModelDataRoot { paths in
      let agent = FakeAgentService()
      let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one"], agent: agent)
      let id = try await library.importDocument(at: source, runOCR: true).document.id
      let result = try await library.summarizePages(documentId: id, request: PageSummaryRequest(selection: .missing))
      #expect(result.unavailableReason == PageSummaryCoordinator.notConfiguredReason)
      #expect(await agent.requests.isEmpty)
    }
  }

  @Test func libraryModelSummarizesAfterOCRWhenAsked() async throws {
    try await withAppModelDataRoot { paths in
      let agent = FakeAgentService()
      let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one", "two"], agent: agent,
                                                      config: summaryConfig(auto: true))
      let model = LibraryViewModel(library: library)
      model.importFiles([source])
      await model.waitForImports()
      try await Task.sleep(for: .milliseconds(20))
      await model.waitForSummaries()
      let id = try #require(model.rows.first?.id)
      #expect(model.summaryConfigured)
      #expect(!model.isSummarizing(id))
      #expect(await model.pageSummary(documentId: id, page: 1)?.summary == "answer")
      #expect(await model.pageSummary(documentId: id, page: 2)?.summary == "answer")
      #expect(await model.pagesNeedingSummary(documentId: id) == 0)
      let revision = model.summaryRevision
      #expect(revision > 0)

      await agent.enqueue(.success("Shorter."))
      await model.summarizePages(documentId: id, range: .pages("2"), instruction: "Shorter")
      #expect(await model.pageSummary(documentId: id, page: 2)?.summary == "Shorter.")
      #expect(model.summaryRevision > revision)
      await model.summarizePages(documentId: id, range: .pages("3"))
      #expect(model.alert?.contains("exceeds page count 2") == true)
    }
  }

  @Test func libraryModelLeavesSummariesAloneWhenAutoRunIsOff() async throws {
    try await withAppModelDataRoot { paths in
      let agent = FakeAgentService()
      let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one"], agent: agent,
                                                      config: summaryConfig(auto: false))
      let model = LibraryViewModel(library: library)
      model.importFiles([source])
      await model.waitForImports()
      await model.waitForSummaries()
      let id = try #require(model.rows.first?.id)
      #expect(await model.pageSummary(documentId: id, page: 1) == nil)
      #expect(await model.pagesNeedingSummary(documentId: id) == 1)
      #expect(await agent.requests.isEmpty)
    }
  }

  @Test func summaryConfigKeysValidateAndDefault() throws {
    var config = StriaConfig.defaults
    #expect(config.summary == StriaConfig.SummaryConfig())
    #expect(!config.summary.autoRunAfterOCR)
    #expect(config.summary.language == PageSummaryLanguage.auto)
    config = try ConfigKeyPath.setting("summary.vendor", to: "codex", in: config)
    config = try ConfigKeyPath.setting("summary.language", to: "Korean", in: config)
    config = try ConfigKeyPath.setting("summary.autoRunAfterOCR", to: "true", in: config)
    config = try ConfigKeyPath.setting("summary.prompt", to: "In {language}.", in: config)
    #expect(try ConfigKeyPath.value(of: "summary.language", in: config) == .string("Korean"))
    #expect(try ConfigKeyPath.value(of: "summary.autoRunAfterOCR", in: config) == .bool(true))
    config = try ConfigKeyPath.setting("summary.prompt", to: "null", in: config)
    #expect(config.summary.prompt == nil)
    #expect(throws: StriaError.self) { try ConfigKeyPath.setting("summary.vendor", to: "nope", in: config) }
    #expect(throws: StriaError.self) { try ConfigKeyPath.setting("summary.timeoutSeconds", to: "1", in: config) }
    #expect(throws: StriaError.self) { try ConfigKeyPath.setting("summary.language", to: "null", in: config) }
    let decoded = try JSONDecoder().decode(StriaConfig.self, from: Data(#"{"version":1}"#.utf8))
    #expect(decoded.summary == StriaConfig.SummaryConfig())
    let roundTrip = try JSONDecoder().decode(StriaConfig.self, from: JSONEncoder().encode(config))
    #expect(roundTrip.summary == config.summary)
    #expect(PageSummaryDefaults.prompt.contains(PageSummaryDefaults.placeholder))
  }

  @Test func pagesWithoutOCRTextAreOCRedFirst() async throws {
    try await withAppModelDataRoot { paths in
      let agent = FakeAgentService()
      let ocr = FakeOCRService()
      var config = summaryConfig()
      config.ocr.autoRunOnImport = false
      let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one", "two"], ocr: ocr, agent: agent, config: config)
      let id = try await library.importDocument(at: source, runOCR: false).document.id
      #expect(try await library.pagesNeedingSummary(documentId: id) == [1, 2])
      #expect(try await library.pageSummaryCounts()[id] == PageSummaryCounts(notOCRed: 2, total: 2))
      let phases = PhaseRecorder()
      let result = try await library.summarizePages(documentId: id, request: PageSummaryRequest(selection: .missing)) {
        phases.record($0.phase)
      }
      #expect(result.ocred == [1, 2])
      #expect(result.summarized == [1, 2])
      #expect(result.skipped.isEmpty)
      #expect(phases.values.first == .ocr)
      #expect(phases.values.last == .summary)
      #expect(await ocr.requests.count == 2)
      #expect(try await library.pageSummaryCounts()[id] == PageSummaryCounts(done: 2, total: 2))
    }
  }

  @Test func withoutAnOCRVendorPagesWithoutTextAreReportedSkipped() async throws {
    try await withAppModelDataRoot { paths in
      let agent = FakeAgentService()
      var config = summaryConfig()
      config.ocr.vendor = nil
      config.ocr.autoRunOnImport = false
      let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one"], agent: agent, config: config)
      let id = try await library.importDocument(at: source, runOCR: false).document.id
      let result = try await library.summarizePages(documentId: id, request: PageSummaryRequest(selection: .pages([1])))
      #expect(result.skipped == [1])
      #expect(result.ocrUnavailableReason == OCRCoordinator.notConfiguredReason)
      let report = PageSummaryRunReport(outcome: .finished(result), finishedAt: Date())
      #expect(report.isProblem)
      #expect(report.text.hasPrefix("0 summarized, 1 skipped (no OCR text: p. 1)."))
      #expect(report.text.contains("OCR vendor is not configured"))
      #expect(await agent.requests.isEmpty)
    }
  }

  @Test func runsCanBeCancelledAndQueuedRunsDropped() async throws {
    try await withAppModelDataRoot { paths in
      let agent = FakeAgentService()
      let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one", "two", "three"], agent: agent,
                                                      config: summaryConfig())
      let model = LibraryViewModel(library: library)
      model.importFiles([source])
      await model.waitForImports()
      let id = try #require(model.rows.first?.id)
      await agent.setDelay(.milliseconds(300))
      let first = Task { await model.summarizePages(documentId: id, range: .all) }
      let second = Task { await model.summarizePages(documentId: id, range: .pages("1")) }
      for _ in 0..<100 where model.summaryProgress[id]?.currentPage == nil { try await Task.sleep(for: .milliseconds(10)) }
      #expect(model.isSummarizing(id))
      #expect(model.rows.first?.summaryProgress != nil)
      #expect(model.queuedSummaryRuns[id] == 1)
      model.cancelSummaries(documentId: id)
      await first.value
      await second.value
      await model.waitForSummaries()
      #expect(!model.isSummarizing(id))
      #expect(model.summaryReports[id]?.outcome == .cancelled)
      #expect(model.queuedSummaryRuns[id] == nil)
      #expect(await agent.requests.count == 1)
      #expect(model.rows.first?.summaryProgress == nil)

      await agent.setDelay(.zero)
      await model.summarizePages(documentId: id, range: .remaining)
      guard case .finished(let result)? = model.summaryReports[id]?.outcome else {
        Issue.record("Expected a finished run")
        return
      }
      #expect(result.summarized == [1, 2, 3])
      #expect(model.summaryReports[id]?.text == "3 summarized.")
      #expect(model.rows.first?.summaries?.done == 3)
    }
  }
}

final class PhaseRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [PageSummaryPhase] = []
  var values: [PageSummaryPhase] { lock.lock(); defer { lock.unlock() }; return recorded }
  func record(_ phase: PageSummaryPhase) { lock.lock(); recorded.append(phase); lock.unlock() }
}
