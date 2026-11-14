import StriaCore

public actor FakeAgentService: AgentService {
  private var scripted: [Result<String, ServiceError>] = []
  public private(set) var requests: [AgentRequest] = []
  private var delay: Duration = .zero
  public init() {}
  /// Makes every answer wait (cancellation tests).
  public func setDelay(_ delay: Duration) { self.delay = delay }
  public func enqueue(_ result: Result<String, ServiceError>) { scripted.append(result) }
  public func ask(_ request: AgentRequest, onChunk: @escaping AnswerChunkHandler) async throws -> AgentAnswer {
    requests.append(request)
    if delay > .zero { try await Task.sleep(for: delay) }
    let fallback = request.contextPages.first.map { "answer [\($0.docId) p.\($0.page)]" } ?? "answer"
    switch scripted.isEmpty ? .success(fallback) : scripted.removeFirst() {
    case .success(let text):
      // Stream in two pieces so callers can observe partial answers.
      let split = text.index(text.startIndex, offsetBy: text.count / 2)
      onChunk(String(text[..<split]))
      onChunk(String(text[split...]))
      return AgentAnswer(text: text)
    case .failure(let error): throw error
    }
  }
}
