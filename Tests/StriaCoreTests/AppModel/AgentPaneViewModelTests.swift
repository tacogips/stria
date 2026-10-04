import Foundation
import StriaCore
import Testing

@Suite @MainActor struct AgentPaneViewModelTests {
@Test func agentPaneDescribesScopesAndSendsSuccessfulAsk() async throws {
  try await withAppModelDataRoot { paths in
    let fakeAgent = FakeAgentService()
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one", "two", "three"], agent: fakeAgent)
    let imported = try await library.importDocument(at: source, runOCR: false)
    let reader = ReaderViewModel(library: library, documentId: imported.document.id)
    try await reader.open()
    let pane = AgentPaneViewModel(library: library, reader: reader)
    reader.pageDidChange(to: 2)
    #expect(pane.scopeDescription == "Sees page 2")
    pane.scope = .nearby
    reader.pageDidChange(to: 1)
    #expect(pane.scopeDescription == "Sees pages 1-2")
    pane.scope = .document
    #expect(pane.scopeDescription == "Sees up to 4 relevant pages of fixture, including page 1")

    pane.scope = .page
    reader.pageDidChange(to: 2)
    pane.input = "What is here?"
    await pane.send()
    #expect(pane.threadId != nil)
    #expect(pane.transcript.count == 2)
    #expect(pane.threads.count == 1)
    #expect(pane.threads.first?.firstQuestion == "What is here?")
    #expect(pane.threads.first?.messageCount == 2)
    #expect(pane.input.isEmpty)
    await reader.close()
  }
}

@Test func agentPaneShowsPersistedFailureAndUnavailableNotice() async throws {
  try await withAppModelDataRoot { paths in
    let fakeAgent = FakeAgentService()
    await fakeAgent.enqueue(.failure(.failed("provider failed")))
    await fakeAgent.enqueue(.failure(.unavailable("credentials unavailable")))
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one"], agent: fakeAgent)
    let imported = try await library.importDocument(at: source, runOCR: false)
    let reader = ReaderViewModel(library: library, documentId: imported.document.id)
    try await reader.open()
    let pane = AgentPaneViewModel(library: library, reader: reader)
    pane.input = "fail"
    await pane.send()
    #expect(pane.threadId != nil)
    #expect(pane.transcript.last?.status == .error)
    #expect(pane.transcript.last?.content.contains("provider failed") == true)
    #expect(pane.notice == nil)
    let historyBeforeUnavailable = try await library.history(documentId: imported.document.id)

    pane.newChat()
    pane.input = "unavailable"
    await pane.send()
    #expect(pane.notice?.contains("credentials unavailable") == true)
    #expect(pane.transcript.isEmpty)
    #expect(try await library.history(documentId: imported.document.id) == historyBeforeUnavailable)
    #expect(try await library.store.agentRuns(documentId: imported.document.id).count == 1)
    await reader.close()
  }
}

@Test func agentPaneCitationPagesAndHistorySelectionNavigate() async throws {
  try await withAppModelDataRoot { paths in
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["1", "2", "3", "4"])
    let imported = try await library.importDocument(at: source, runOCR: false)
    let reader = ReaderViewModel(library: library, documentId: imported.document.id)
    try await reader.open()
    let pane = AgentPaneViewModel(library: library, reader: reader)
    let message = ChatMessageRecord(
      id: 1, threadId: "thread", role: .assistant, status: .ok,
      content: "[\(imported.document.id) p.3] [ffffffffffffffff p.2] [\(imported.document.id) p.3]",
      documentId: imported.document.id, pageNumber: 4, createdAt: Date()
    )
    #expect(pane.citationPages(in: message) == [3])
    let thread = ThreadOverview(threadId: "thread", documentId: imported.document.id, pageNumber: 4, firstQuestion: "q",
                                summary: nil, isSummaryCurrent: false, messageCount: 1, lastMessageId: 1, updatedAt: Date())
    await pane.selectThread(thread)
    #expect(reader.requestedPage == 4)
    #expect(pane.threadId == "thread")
    await reader.close()
  }
}

@Test func pendingQuestionIsShownThenReplacedOrRemoved() async throws {
  try await withAppModelDataRoot { paths in
    let fakeAgent = FakeAgentService()
    await fakeAgent.enqueue(.failure(.unavailable("no credentials")))
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one"], agent: fakeAgent)
    let imported = try await library.importDocument(at: source, runOCR: false)
    let reader = ReaderViewModel(library: library, documentId: imported.document.id)
    try await reader.open()
    let pane = AgentPaneViewModel(library: library, reader: reader, historyDebounce: .milliseconds(10))
    pane.input = "first"
    await pane.send()
    #expect(pane.transcript.isEmpty)
    #expect(pane.notice == "no credentials")

    pane.input = "second"
    pane.submit()
    try await Task.sleep(for: .milliseconds(50))
    await pane.send()
    #expect(pane.transcript.map(\.role) == [.user, .assistant])
    #expect(pane.transcript.allSatisfy { $0.id != AgentPaneViewModel.pendingMessageID })

    pane.historyMode = .page
    pane.scheduleHistoryReload()
    pane.scheduleHistoryReload()
    try await Task.sleep(for: .milliseconds(100))
    #expect(pane.threads.count == 1)
    await reader.close()
  }
}

@Test func conversationsAreSummarizedFromTheFirstQuestion() async throws {
  try await withAppModelDataRoot { paths in
    let fakeAgent = FakeAgentService()
    var config = StriaConfig.testing
    config.agent.autoSummarize = true
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["one", "two"], agent: fakeAgent, config: config)
    let imported = try await library.importDocument(at: source, runOCR: false)
    let reader = ReaderViewModel(library: library, documentId: imported.document.id)
    try await reader.open()
    let pane = AgentPaneViewModel(library: library, reader: reader)
    await fakeAgent.enqueue(.success("first answer"))
    await fakeAgent.enqueue(.success("```\nThe user asked about page one.\n```"))
    pane.input = "What is on page one?"
    await pane.send()
    let thread = try #require(pane.threadId)
    for _ in 0..<100 where pane.threads.first?.summary == nil { try await Task.sleep(for: .milliseconds(20)) }
    let overview = try #require(pane.threads.first)
    #expect(overview.summary == "The user asked about page one.")
    #expect(overview.isSummaryCurrent)
    #expect(overview.firstQuestion == "What is on page one?")
    let summaryRequest = try #require(await fakeAgent.requests.last)
    #expect(summaryRequest.systemPrompt == AgentDefaults.summaryPrompt)
    #expect(summaryRequest.contextPages.isEmpty)
    #expect(summaryRequest.question.contains("User: What is on page one?"))
    #expect(summaryRequest.question.contains("Assistant: first answer"))

    // A manual re-summary with a failing vendor keeps the old summary.
    await fakeAgent.enqueue(.failure(.failed("down")))
    await pane.summarize(threadId: thread)
    #expect(pane.threads.first?.summary == "The user asked about page one.")
    #expect(pane.notice?.contains("down") == true)
    await reader.close()
  }
}

@Test func previousChatsResumeNewestFirstAndKnowTheirStartPage() async throws {
  try await withAppModelDataRoot { paths in
    let (library, source) = try makeAppModelFixture(paths: paths, pageTexts: ["1", "2", "3"])
    let imported = try await library.importDocument(at: source, runOCR: false)
    let reader = ReaderViewModel(library: library, documentId: imported.document.id)
    try await reader.open()
    let pane = AgentPaneViewModel(library: library, reader: reader)
    #expect(await pane.resumePreviousChat() == false)
    #expect(pane.notice == "No earlier conversation about this PDF.")

    reader.pageDidChange(to: 1)
    pane.input = "older"
    await pane.send()
    let older = try #require(pane.threadId)
    pane.newChat()
    reader.pageDidChange(to: 3)
    pane.input = "newer"
    await pane.send()
    let newer = try #require(pane.threadId)
    reader.pageDidChange(to: 2)
    pane.input = "follow-up on another page"
    await pane.send()
    #expect(pane.conversationStartPage == 3)
    pane.goToConversationStart()
    #expect(reader.requestedPage == 3)

    pane.newChat()
    #expect(pane.conversationStartPage == nil)
    #expect(await pane.resumePreviousChat())
    #expect(pane.threadId == newer)
    #expect(await pane.resumePreviousChat())
    #expect(pane.threadId == older)
    #expect(pane.conversationStartPage == 1)
    #expect(await pane.resumePreviousChat() == false)
    #expect(pane.notice == "No older conversation about this PDF.")
    #expect(pane.threadId == older)
    await reader.close()
  }
}
}
