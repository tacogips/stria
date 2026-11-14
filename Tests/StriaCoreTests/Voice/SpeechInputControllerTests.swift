import Foundation
import StriaCore
import Testing

@Suite @MainActor struct SpeechInputControllerTests {
  @Test func toggleStartsAndStopsAndKeepsTypedText() async throws {
    let fixture = VoiceComposerFixture()
    fixture.controller.toggle()
    #expect(fixture.controller.state == .requestingPermission)
    try await waitForVoice { fixture.controller.state.isRecording }
    #expect(fixture.engine.starts == 1)
    fixture.engine.events?(.partial("first"))
    #expect(fixture.input == "Typed question first")
    fixture.engine.events?(.partial("revised"))
    #expect(fixture.input == "Typed question revised")
    fixture.engine.events?(.level(0.7))
    #expect(fixture.controller.state == .recording(level: 0.7))
    fixture.controller.toggle()
    #expect(fixture.controller.state == .transcribing)
    try await waitForVoice { fixture.controller.state == .idle }
    #expect(fixture.engine.stops == 1)
    #expect(fixture.input == "Typed question final words")
    #expect(fixture.submits == 0)
  }

  @Test func cancellationDiscardsOnlyDictatedRangeAndIgnoresLateResults() async throws {
    let fixture = VoiceComposerFixture()
    fixture.controller.toggle()
    try await waitForVoice { fixture.controller.state.isRecording }
    fixture.engine.events?(.partial("spoken"))
    fixture.input += " typed after"
    fixture.controller.cancel()
    #expect(fixture.input == "Typed question typed after")
    #expect(fixture.controller.state == .idle)
    #expect(fixture.engine.cancels == 1)
    fixture.engine.events?(.final("late"))
    #expect(fixture.input == "Typed question typed after")
  }

  @Test func partialsPreserveEditsBeforeAndAfterAndUnicode() async throws {
    let fixture = VoiceComposerFixture()
    fixture.input = "日本語"
    fixture.controller.toggle()
    try await waitForVoice { fixture.controller.state.isRecording }
    fixture.engine.events?(.partial("one"))
    fixture.input = "prefix " + fixture.input
    fixture.engine.events?(.partial("two"))
    fixture.input += " suffix"
    fixture.engine.events?(.final("three"))
    #expect(fixture.input == "prefix 日本語 three suffix")
  }

  @Test func errorKeepsTextAndSetsNotice() async throws {
    let fixture = VoiceComposerFixture()
    fixture.engine.failure = SpeechInputError("vendor failed")
    fixture.controller.toggle()
    try await waitForVoice { fixture.controller.state.isRecording }
    fixture.engine.events?(.partial("spoken"))
    fixture.controller.toggle()
    try await waitForVoice { !fixture.controller.state.isActive }
    #expect(fixture.input == "Typed question spoken")
    #expect(fixture.notice == "vendor failed")
    #expect(fixture.controller.state == .failed(message: "vendor failed"))
  }

  @Test func permissionDenialKeepsTextAndDoesNotRecord() async throws {
    let fixture = VoiceComposerFixture()
    fixture.engine.permissionFailure = SpeechInputError("Enable microphone in System Settings")
    fixture.controller.toggle()
    try await waitForVoice { !fixture.controller.state.isActive }
    #expect(fixture.engine.starts == 0)
    #expect(fixture.input == "Typed question")
    #expect(fixture.notice?.contains("System Settings") == true)
  }

  @Test func emptyFinalDoesNotAutoSend() async throws {
    let fixture = VoiceComposerFixture()
    fixture.config.autoSend = true
    fixture.controller.toggle()
    try await waitForVoice { fixture.controller.state.isRecording }
    fixture.engine.events?(.final(""))
    #expect(fixture.submits == 0)
    #expect(fixture.input == "Typed question")
  }

  @Test func maximumDurationStopsWithInjectedClock() async throws {
    let fixture = VoiceComposerFixture()
    fixture.config.maxSeconds = 10
    let ticks = VoiceTestTicks()
    let controller = SpeechInputController(config: { fixture.config }, makeEngine: { _ in fixture.engine },
      readInput: { fixture.input }, writeInput: { fixture.input = $0 }, notice: { fixture.notice = $0 }, submit: {},
      sleep: { _ in try await ticks.sleep() })
    controller.toggle()
    try await waitForVoice { controller.state.isRecording }
    for index in 1...10 {
      let deadline = ContinuousClock.now + .seconds(3)
      while !(await ticks.waiting), ContinuousClock.now < deadline { await Task.yield() }
      try #require(await ticks.waiting)
      await ticks.tick()
      try await waitForVoice { controller.elapsedSeconds == index }
    }
    try await waitForVoice { controller.state == .idle }
    #expect(fixture.engine.stops == 1)
    #expect(fixture.input == "Typed question final words")
  }

  @Test func cancellationDuringPermissionsAndPreparationNeverStartsRecording() async throws {
    for preparing in [false, true] {
      let fixture = VoiceComposerFixture()
      let gate = VoiceTestTicks()
      if preparing { fixture.engine.startGate = gate } else { fixture.engine.permissionGate = gate }
      fixture.controller.toggle()
      let deadline = ContinuousClock.now + .seconds(3)
      while !(await gate.waiting), ContinuousClock.now < deadline { await Task.yield() }
      try #require(await gate.waiting)
      #expect(fixture.controller.state == (preparing ? .preparing : .requestingPermission))
      fixture.controller.cancel()
      await gate.tick()
      await Task.yield()
      #expect(fixture.controller.state == .idle)
      #expect(fixture.input == "Typed question")
      #expect(fixture.engine.cancels == 1)
    }
  }

  @Test func staleEventsCannotChangeANewRecording() async throws {
    let fixture = VoiceComposerFixture()
    fixture.controller.toggle()
    try await waitForVoice { fixture.controller.state.isRecording }
    let oldEvents = fixture.engine.events
    fixture.controller.cancel()
    fixture.controller.toggle()
    try await waitForVoice { fixture.controller.state.isRecording }
    oldEvents?(.final("old transcript"))
    oldEvents?(.failed("old error"))
    #expect(fixture.controller.state.isRecording)
    #expect(fixture.notice == nil)
    #expect(fixture.input == "Typed question")
    fixture.controller.cancel()
  }

  @Test func liveFailureReportsNoticeAndKeepsPartialText() async throws {
    let fixture = VoiceComposerFixture()
    fixture.controller.toggle()
    try await waitForVoice { fixture.controller.state.isRecording }
    fixture.engine.events?(.partial("spoken words"))
    fixture.engine.events?(.failed("microphone interrupted"))
    #expect(fixture.input == "Typed question spoken words")
    #expect(fixture.notice == "microphone interrupted")
    #expect(fixture.controller.state == .failed(message: "microphone interrupted"))
  }

  @Test func autoSendUsesAgentPaneSubmit() async throws {
    try await withAppModelDataRoot { paths in
      var config = StriaConfig.testing
      config.voice.autoSend = true
      config.agent.autoSummarize = false
      let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["page"], config: config)
      let document = try await library.importDocument(at: source, runOCR: false)
      let reader = ReaderViewModel(library: library, documentId: document.document.id)
      try await reader.open()
      let engine = FakeSpeechEngine()
      let pane = AgentPaneViewModel(library: library, reader: reader, processEnvironment: [:], speechEngineFactory: { _ in engine })
      pane.input = "Typed"
      pane.toggleDictation()
      try await waitForVoice { pane.dictationState.isRecording }
      engine.events?(.final("question"))
      try await waitForVoice { pane.transcript.count == 2 && !pane.inFlight }
      #expect(pane.transcript.first?.content == "Typed question")
      #expect(pane.input.isEmpty)
      await reader.close()
    }
  }
}
