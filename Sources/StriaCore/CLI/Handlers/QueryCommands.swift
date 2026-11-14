import Foundation

enum QueryCommands {
  static func run(_ command: CLICommand, library: StriaLibrary) async throws -> any Encodable {
    switch command {
    case .search(let query, let docId, let limit):
      guard limit.map({ (1...100).contains($0) }) ?? true else {
        throw StriaError.usage("search --limit must be between 1 and 100")
      }
      let response = try await library.search(query: query, documentId: docId, limit: limit ?? 10)
      let results = response.results.map {
        SearchOutput.Result(docId: $0.docId, title: $0.title, page: $0.page, snippet: $0.snippet,
                            score: $0.score, imagePath: $0.imagePath, imageCached: $0.imageCached)
      }
      return SearchOutput(query: response.query, matchMode: response.matchMode, results: results)
    case .ask(let question, let docId, let page, let query, let limit, let thread, let vendor, let model):
      let context: AskContext
      if let docId, let page {
        context = .page(docId: docId, page: page)
      } else if let docId {
        context = .document(docId: docId, anchorPage: nil)
      } else {
        context = .library
      }
      let response = try await library.ask(AskRequest(question: question, context: context, retrievalQuery: query,
                                                      limit: limit, threadId: thread,
                                                      selection: vendor.map { AgentSelection(vendor: $0, model: model) }))
      let citations = response.citations.map {
        AskOutput.OutputCitation(docId: $0.docId, title: $0.title, page: $0.page, imagePath: $0.imagePath)
      }
      let contextPages = response.contextPages.map {
        AskOutput.OutputCitation(docId: $0.docId, title: $0.title, page: $0.page, imagePath: $0.imagePath)
      }
      return AskOutput(threadId: response.threadId, answer: response.answer, vendor: response.vendor,
                       model: response.model, runId: response.runId, citations: citations, contextPages: contextPages)
    case .history(let docId, let page, let limit):
      let messages = try await library.history(documentId: docId, page: page, limit: limit ?? 50).map { item in
        HistoryMessageOutput(
          id: item.id, threadId: item.threadId, role: item.role, status: item.status, content: item.content,
          docId: item.documentId, page: item.pageNumber, vendor: item.vendor, model: item.model,
          runId: item.agentRunId,
          citations: item.citations.map { HistoryCitationOutput(docId: $0.docId, page: $0.page) }, createdAt: item.createdAt
        )
      }
      return HistoryOutput(messages: messages)
    default:
      throw StriaError.usage("Not a query command")
    }
  }
}
