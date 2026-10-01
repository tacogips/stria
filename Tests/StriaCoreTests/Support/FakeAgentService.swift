import StriaCore

public actor FakeAgentService: AgentService {
  private var scripted: [Result<String, ServiceError>] = []
  public private(set) var requests: [AgentRequest] = []
  public init() {}
  public func enqueue(_ result: Result<String, ServiceError>) { scripted.append(result) }
  public func ask(_ request: AgentRequest) async throws -> AgentAnswer {
    requests.append(request)
    let fallback = request.contextPages.first.map { "answer [\($0.docId) p.\($0.page)]" } ?? "answer"
    switch scripted.isEmpty ? .success(fallback) : scripted.removeFirst() {
    case .success(let text): return AgentAnswer(text: text)
    case .failure(let error): throw error
    }
  }
}
