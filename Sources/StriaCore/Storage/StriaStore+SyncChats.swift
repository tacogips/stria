import Foundation

extension StriaStore {
  func syncThreads() throws -> [SyncThread] {
    let row = try database.prepare("""
      SELECT id,document_id,page_number,scope,title,summary,summary_through_message_id,created_at,updated_at FROM chat_threads ORDER BY id
      """)
    var threads: [SyncThread] = []
    while try row.step() {
      guard let id = row.string(0), let scope = row.string(3).flatMap(ChatScope.init(rawValue:)),
            let created = row.string(7).flatMap(StriaDateFormat.date(from:)),
            let updated = row.string(8).flatMap(StriaDateFormat.date(from:)) else { throw StriaError.database("Invalid sync thread") }
      let messages = try threadMessages(threadId: id)
      let through = row.isNull(6) ? nil : messages.firstIndex { $0.id == row.int64(6) }
      threads.append(SyncThread(id: id, documentId: row.string(1), pageNumber: row.isNull(2) ? nil : row.int(2), scope: scope,
                                title: row.string(4), summary: row.string(5), summaryThroughIndex: through,
                                createdAt: created, updatedAt: updated, messages: messages.map(SyncMessage.init)))
    }
    return threads
  }

  func applySyncThread(_ thread: SyncThread) throws {
    if let index = thread.summaryThroughIndex, !thread.messages.indices.contains(index) {
      throw StriaError.io("Invalid chat summary coverage")
    }
    try database.transaction {
      let delete = try database.prepare("DELETE FROM chat_threads WHERE id=?")
      try delete.bind(thread.id, at: 1)
      _ = try delete.step()
      let insert = try database.prepare("""
        INSERT INTO chat_threads(id,document_id,page_number,scope,title,summary,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)
        """)
      try insert.bind(thread.id, at: 1).bind(thread.documentId, at: 2).bind(thread.pageNumber, at: 3)
        .bind(thread.scope.rawValue, at: 4).bind(thread.title, at: 5).bind(thread.summary, at: 6)
        .bind(StriaDateFormat.string(from: thread.createdAt), at: 7).bind(StriaDateFormat.string(from: thread.updatedAt), at: 8)
      _ = try insert.step()
      var through: Int64?
      for (index, message) in thread.messages.enumerated() {
        let row = try database.prepare("""
          INSERT INTO chat_messages(thread_id,role,status,content,document_id,page_number,vendor,model,citations_json,created_at)
          VALUES(?,?,?,?,?,?,?,?,?,?)
          """)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let citations = String(data: try encoder.encode(message.citations), encoding: .utf8)
        try row.bind(thread.id, at: 1).bind(message.role.rawValue, at: 2).bind(message.status.rawValue, at: 3)
          .bind(message.content, at: 4).bind(message.documentId, at: 5).bind(message.page, at: 6)
          .bind(message.vendor, at: 7).bind(message.model, at: 8).bind(citations, at: 9)
          .bind(StriaDateFormat.string(from: message.createdAt), at: 10)
        _ = try row.step()
        if index == thread.summaryThroughIndex { through = database.lastInsertRowID }
      }
      let update = try database.prepare("UPDATE chat_threads SET summary_through_message_id=? WHERE id=?")
      if let through { try update.bind(through, at: 1) } else { try update.bindNull(at: 1) }
      try update.bind(thread.id, at: 2)
      _ = try update.step()
    }
  }
}
