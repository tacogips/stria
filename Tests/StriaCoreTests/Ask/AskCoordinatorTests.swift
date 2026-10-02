import Foundation
import StriaCore
import Testing

@Suite("AskCoordinatorTests") struct AskCoordinatorTests {
  @Test func persistsSuccessFailureAndUnavailableCorrectly() async throws {
    try await withTestDataRoot { paths in
      let store = try await prepareAskDocument(paths: paths, id: "doc", texts: [1: "OCR text"])
      let fake = FakeAgentService()
      let environment = makeTestEnvironment(paths: paths, agent: fake)
      let library = try StriaLibrary.open(environment: environment)
      let request = AskRequest(question: "What?", context: .page(docId: "doc", page: 1))
      let response = try await library.ask(request)
      #expect(response.answer.contains("doc p.1"))
      #expect(response.citations.count == 1)
      #expect(FileManager.default.fileExists(atPath: response.citations[0].imagePath))
      let captured = await fake.requests
      #expect(captured.first?.contextPages.first?.ocrText == "OCR text")
      #expect(captured.first?.contextPages.first.map { FileManager.default.fileExists(atPath: $0.pngPath.path) } == true)
      let messages = try await library.history(documentId: "doc", page: 1)
      #expect(messages.count == 2)
      #expect(messages.allSatisfy { $0.documentId == "doc" && $0.pageNumber == 1 })
      #expect(try await store.agentRuns(documentId: "doc").filter { $0.kind == .ask }.count == 1)
      let jsonl = try String(contentsOf: paths.runLog(for: Date()), encoding: .utf8)
      #expect(jsonl.split(separator: "\n").count == 1)

      await fake.enqueue(.failure(.failed("model failed")))
      do {
        _ = try await library.ask(request)
        Issue.record("Expected service failure")
      } catch let error as StriaError { #expect(error.code == .serviceFailed) }
      let afterFailure = try await library.history(documentId: "doc", page: 1)
      #expect(afterFailure.suffix(2).map(\.status) == [.ok, .error])
      #expect(try await store.agentRuns(documentId: "doc").filter { $0.kind == .ask }.count == 2)

      await fake.enqueue(.failure(.unavailable("missing configuration")))
      do {
        _ = try await library.ask(request)
        Issue.record("Expected unavailable error")
      } catch let error as StriaError { #expect(error.code == .serviceUnavailable) }
      #expect(try await library.history(documentId: "doc", page: 1).count == afterFailure.count)
      #expect(try await store.agentRuns(documentId: "doc").filter { $0.kind == .ask }.count == 2)
    }
  }

  @Test func noRelevantPagesSkipsModelAndThreadHistoryIsReused() async throws {
    try await withTestDataRoot { paths in
      _ = try await prepareAskDocument(paths: paths, id: "doc", texts: [1: "distinctive phrase"])
      let fake = FakeAgentService()
      let library = try StriaLibrary.open(environment: makeTestEnvironment(paths: paths, agent: fake))
      do {
        _ = try await library.ask(AskRequest(question: "not present anywhere", context: .library))
        Issue.record("Expected no relevant pages")
      } catch let error as StriaError { #expect(error.code == .noRelevantPages) }
      #expect(await fake.requests.isEmpty)
      let first = try await library.ask(AskRequest(question: "distinctive", context: .page(docId: "doc", page: 1), threadId: "thread"))
      _ = try await library.ask(AskRequest(question: "again", context: .page(docId: "doc", page: 1), threadId: first.threadId))
      let requests = await fake.requests
      #expect(requests.count == 2)
      #expect(requests[1].history.count == 2)
    }
  }

  @Test func toolsSectionIsSentOnlyToCLIVendorsWithTheDataRoot() async throws {
    try await withTestDataRoot { paths in
      _ = try await prepareAskDocument(paths: paths, id: "doc", texts: [1: "text"])
      let fake = FakeAgentService()
      let api = try StriaLibrary.open(environment: makeTestEnvironment(paths: paths, agent: fake))
      _ = try await api.ask(AskRequest(question: "q", context: .page(docId: "doc", page: 1)))
      var config = StriaConfig.testing
      config.agent.vendor = "claude-code"
      config.agent.apiKeyEnvironment = nil
      let cli = try StriaLibrary.open(environment: makeTestEnvironment(paths: paths, agent: fake, config: config))
      _ = try await cli.ask(AskRequest(question: "q", context: .page(docId: "doc", page: 1)))
      let requests = await fake.requests
      #expect(requests.count == 2)
      #expect(!requests[0].systemPrompt.contains("You may run the stria command"))
      if StriaToolsPrompt.locateExecutable() != nil {
        #expect(requests[1].systemPrompt.contains("You may run the stria command"))
        #expect(requests[1].systemPrompt.contains("--home"))
        #expect(requests[1].systemPrompt.contains("docId doc"))
        #expect(requests[1].systemPrompt.contains(paths.root.path.replacingOccurrences(of: "'", with: "'\\''")) == true)
      }
      let section = StriaToolsPrompt.section(executable: URL(fileURLWithPath: "/usr/local/bin/stria"),
                                             dataRoot: URL(fileURLWithPath: "/tmp/my root"), currentDocumentId: nil)
      #expect(section.contains("'/tmp/my root'"))
      #expect(section.contains("whole library"))
      #expect(!section.contains("remove"))
      #expect(StriaToolsPrompt.locateExecutable(environment: ["PATH": "/nowhere"], fileExists: { _ in false }) == nil)
      #expect(StriaToolsPrompt.locateExecutable(environment: ["PATH": "/x"], fileExists: { $0 == "/x/stria" })?.path == "/x/stria")
    }
  }

  @Test func threadFollowUpReusesPreviouslyCitedPages() async throws {
    try await withTestDataRoot { paths in
      _ = try await prepareAskDocument(paths: paths, id: "doc", texts: [1: "zebra quantum lattice", 2: "unrelated"])
      let fake = FakeAgentService()
      await fake.enqueue(.success("It is on [doc p.1]."))
      let library = try StriaLibrary.open(environment: makeTestEnvironment(paths: paths, agent: fake))
      let first = try await library.ask(AskRequest(question: "Which page mentions zebra?", context: .library))
      #expect(first.citations.map(\.page) == [1])
      let followUp = try await library.ask(AskRequest(question: "What else is on that page?", context: .library, threadId: first.threadId))
      #expect(followUp.contextPages.map(\.page) == [1])
      let requests = await fake.requests
      #expect(requests.count == 2)
      #expect(requests[1].history.count == 2)
      await #expect(throws: StriaError.self) {
        _ = try await library.ask(AskRequest(question: "What else is on that page?", context: .library))
      }
    }
  }

  @Test func streamedChunksConcatenateToTheAnswer() async throws {
    try await withTestDataRoot { paths in
      _ = try await prepareAskDocument(paths: paths, id: "doc", texts: [1: "OCR text"])
      let fake = FakeAgentService()
      await fake.enqueue(.success("streamed answer [doc p.1]"))
      let library = try StriaLibrary.open(environment: makeTestEnvironment(paths: paths, agent: fake))
      let chunks = ChunkRecorder()
      let request = AskRequest(question: "What?", context: .page(docId: "doc", page: 1)) { chunks.append($0) }
      let response = try await library.ask(request)
      #expect(chunks.joined() == response.answer)
      #expect(chunks.count == 2)
    }
  }

  @Test func documentAnchorAndTextBudgetAreHonored() async throws {
    try await withTestDataRoot { paths in
      var config = StriaConfig.testing
      config.agent.maxContextCharacters = 10
      config.agent.maxImages = 2
      _ = try await prepareAskDocument(paths: paths, id: "doc", texts: [1: "12345678", 2: "abcdefgh"])
      let fake = FakeAgentService()
      let library = try StriaLibrary.open(environment: makeTestEnvironment(paths: paths, agent: fake, config: config))
      _ = try await library.ask(AskRequest(question: "", context: .nearby(docId: "doc", page: 1)))
      let contexts = await fake.requests.first?.contextPages
      #expect(contexts?.map(\.page) == [1, 2])
      #expect(contexts?.map(\.ocrText) == ["12345678", "ab"])
    }
  }
}

private final class ChunkRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var chunks: [String] = []
  func append(_ chunk: String) { lock.lock(); chunks.append(chunk); lock.unlock() }
  func joined() -> String { lock.lock(); defer { lock.unlock() }; return chunks.joined() }
  var count: Int { lock.lock(); defer { lock.unlock() }; return chunks.count }
}
