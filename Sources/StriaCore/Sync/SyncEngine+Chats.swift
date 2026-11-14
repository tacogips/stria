import Foundation

extension SyncEngine {
  func syncChats(folder: URL, options: SyncConfig, pending: Set<String>, report: inout SyncReport) async {
    do {
      let directory = folder.appendingPathComponent("chats")
      let local = Dictionary(uniqueKeysWithValues: try await library.store.syncThreads().map { ($0.id, $0) })
      let urls = try files.children(directory).filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") && !$0.lastPathComponent.hasSuffix(".deleted.json") }
      let ids = Set(local.keys).union(urls.map { $0.deletingPathExtension().lastPathComponent })
      for id in ids.sorted() {
        do {
          guard Self.safeID(id) else { throw StriaError.io("Invalid thread id") }
          let url = directory.appendingPathComponent("\(id).json")
          guard !pending.contains(url.path) else { continue }
          let remote = try files.exists(url) ? files.read(SyncThread.self, at: url) : nil
          if let remote, remote.id != id { throw StriaError.io("Invalid thread identity") }
          let incomingWins = remote.map { $0.updatedAt > local[id]?.updatedAt ?? .distantPast } ?? false
          // Apply toggles to the winning thread, including library-wide chats.
          let documentId = incomingWins ? remote?.documentId : local[id]?.documentId
          if let documentId {
            guard Self.safeID(documentId) else { throw StriaError.io("Invalid chat document id") }
            guard options.documents, try await library.store.document(id: documentId) != nil else { continue }
            let tombstone = folder.appendingPathComponent("documents/\(documentId)/deleted.json")
            guard !pending.contains(tombstone.path), try !files.exists(tombstone) else { continue }
          }
          if let remote, incomingWins {
            try await library.store.applySyncThread(remote); report.chats.pulled += 1
          } else if let thread = local[id], remote == nil || thread.updatedAt > remote?.updatedAt ?? .distantPast {
            try files.write(thread, at: url); report.chats.pushed += 1
          }
        } catch { itemError(error, item: "chat \(id)", report: &report) }
      }
    } catch { itemError(error, item: "chats", report: &report) }
  }
}
