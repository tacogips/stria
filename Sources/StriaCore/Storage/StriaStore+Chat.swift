import Foundation

private struct ChatMessageInsert {
  let threadId: String
  let role: ChatRole
  let status: MessageStatus
  let content: String
  let documentId: String?
  let page: Int?
  let vendor: String?
  let model: String?
  let runId: String?
  let citations: [PageRef]?
  let date: Date
}

extension StriaStore {
  public func persistAskExchange(_ exchange: AskExchange) throws {
    try database.transaction {
      let timestamp = StriaDateFormat.string(from: exchange.createdAt)
      if let thread = exchange.newThread {
        let insert = try database.prepare("""
          INSERT INTO chat_threads(id,document_id,page_number,scope,created_at,updated_at) VALUES(?,?,?,?,?,?)
          """)
        try insert.bind(exchange.threadId, at: 1).bind(thread.documentId, at: 2).bind(thread.pageNumber, at: 3)
          .bind(thread.scope.rawValue, at: 4).bind(timestamp, at: 5).bind(timestamp, at: 6)
        _ = try insert.step()
      } else {
        let update = try database.prepare("UPDATE chat_threads SET updated_at=? WHERE id=?")
        try update.bind(timestamp, at: 1).bind(exchange.threadId, at: 2)
        _ = try update.step()
        guard database.changes > 0 else { throw StriaError.database("Chat thread not found: \(exchange.threadId)") }
      }
      try insertRun(exchange.run)
      try insertMessage(ChatMessageInsert(threadId: exchange.threadId, role: .user, status: .ok, content: exchange.question,
                                          documentId: exchange.anchorDocumentId, page: exchange.anchorPage, vendor: nil,
                                          model: nil, runId: nil, citations: nil, date: exchange.createdAt))
      try insertMessage(ChatMessageInsert(threadId: exchange.threadId, role: .assistant, status: exchange.assistantStatus,
                                          content: exchange.assistantContent, documentId: exchange.anchorDocumentId,
                                          page: exchange.anchorPage, vendor: exchange.vendor, model: exchange.model,
                                          runId: exchange.run.id, citations: exchange.citations, date: exchange.createdAt))
    }
  }

  public func history(documentId: String?, page: Int?, limit: Int) throws -> [ChatMessageRecord] {
    guard page == nil || documentId != nil else { throw StriaError.usage("A page filter requires a document id") }
    guard limit > 0 else { throw StriaError.usage("History limit must be positive") }
    // A library-wide ask has no anchor document, but it still belongs to the
    // history of every document (and page) it cited; both messages of such an
    // exchange share the thread, so the user question is matched through the
    // assistant message's citations.
    let filter: String
    if documentId != nil, page != nil {
      filter = """
        WHERE (document_id=? AND page_number=?) OR (document_id IS NULL AND thread_id IN
          (SELECT thread_id FROM chat_messages WHERE document_id IS NULL AND citations_json LIKE ? ESCAPE '\\'))
        """
    } else if documentId != nil {
      filter = """
        WHERE document_id=? OR (document_id IS NULL AND thread_id IN
          (SELECT thread_id FROM chat_messages WHERE document_id IS NULL AND citations_json LIKE ? ESCAPE '\\'))
        """
    } else {
      filter = ""
    }
    let statement = try database.prepare("""
      SELECT id,thread_id,role,status,content,document_id,page_number,vendor,model,agent_run_id,citations_json,created_at
      FROM chat_messages \(filter) ORDER BY created_at DESC,id DESC LIMIT ?
      """)
    var index: Int32 = 1
    if let documentId { try statement.bind(documentId, at: index); index += 1 }
    if let page { try statement.bind(page, at: index); index += 1 }
    if let documentId {
      let citation = page.map { "{\"docId\":\"\(documentId)\",\"page\":\($0)}" } ?? "{\"docId\":\"\(documentId)\","
      try statement.bind(SearchQueryBuilder.likePattern(term: citation), at: index)
      index += 1
    }
    try statement.bind(limit, at: index)
    var messages: [ChatMessageRecord] = []
    while try statement.step() { messages.append(try chatMessage(statement)) }
    return Array(messages.reversed())
  }

  public func threadMessages(threadId: String) throws -> [ChatMessageRecord] {
    let statement = try database.prepare("""
      SELECT id,thread_id,role,status,content,document_id,page_number,vendor,model,agent_run_id,citations_json,created_at
      FROM chat_messages WHERE thread_id=? ORDER BY id
      """)
    try statement.bind(threadId, at: 1)
    var messages: [ChatMessageRecord] = []
    while try statement.step() { messages.append(try chatMessage(statement)) }
    return messages
  }

  public func agentRuns(documentId: String?) throws -> [AgentRunRecord] {
    let sql = """
      SELECT id,kind,document_id,page_number,vendor,model,status,error,image_count,started_at,finished_at,duration_ms
      FROM agent_runs \(documentId == nil ? "" : "WHERE document_id=?") ORDER BY started_at,rowid
      """
    let statement = try database.prepare(sql)
    if let documentId { try statement.bind(documentId, at: 1) }
    var records: [AgentRunRecord] = []
    while try statement.step() {
      guard let id = statement.string(0), let kind = statement.string(1).flatMap(RunKind.init(rawValue:)),
            let vendor = statement.string(4), let status = statement.string(6).flatMap(RunStatus.init(rawValue:)),
            let started = statement.string(9).flatMap(StriaDateFormat.date(from:)),
            let finished = statement.string(10).flatMap(StriaDateFormat.date(from:)) else { throw StriaError.database("Invalid agent run row") }
      records.append(AgentRunRecord(id: id, kind: kind, documentId: statement.string(2), pageNumber: statement.isNull(3) ? nil : statement.int(3),
                                    vendor: vendor, model: statement.string(5), status: status, error: statement.string(7),
                                    imageCount: statement.int(8), startedAt: started, finishedAt: finished, durationMs: statement.int(11)))
    }
    return records
  }

  private func insertMessage(_ message: ChatMessageInsert) throws {
    let statement = try database.prepare("""
      INSERT INTO chat_messages(thread_id,role,status,content,document_id,page_number,vendor,model,agent_run_id,citations_json,created_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,?)
      """)
    let json: String?
    if let citations = message.citations {
      // Sorted keys keep the stored form `{"docId":"...","page":N}` stable for history matching.
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      json = String(data: try encoder.encode(citations), encoding: .utf8)
    } else {
      json = nil
    }
    try statement.bind(message.threadId, at: 1).bind(message.role.rawValue, at: 2).bind(message.status.rawValue, at: 3)
      .bind(message.content, at: 4).bind(message.documentId, at: 5).bind(message.page, at: 6)
      .bind(message.vendor, at: 7).bind(message.model, at: 8).bind(message.runId, at: 9)
      .bind(json, at: 10).bind(StriaDateFormat.string(from: message.date), at: 11)
    _ = try statement.step()
  }

  private func chatMessage(_ row: Statement) throws -> ChatMessageRecord {
    guard let thread = row.string(1), let role = row.string(2).flatMap(ChatRole.init(rawValue:)),
          let status = row.string(3).flatMap(MessageStatus.init(rawValue:)), let content = row.string(4),
          let date = row.string(11).flatMap(StriaDateFormat.date(from:)) else { throw StriaError.database("Invalid chat message row") }
    let citations: [PageRef]
    if let raw = row.string(10), let data = raw.data(using: .utf8) { citations = (try? JSONDecoder().decode([PageRef].self, from: data)) ?? [] } else { citations = [] }
    return ChatMessageRecord(id: row.int64(0), threadId: thread, role: role, status: status, content: content,
                             documentId: row.string(5), pageNumber: row.isNull(6) ? nil : row.int(6), vendor: row.string(7),
                             model: row.string(8), agentRunId: row.string(9), citations: citations, createdAt: date)
  }
}
