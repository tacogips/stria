import Foundation
public struct AgentRunRecord: Codable, Equatable, Sendable {
  public var id: String; public var kind: RunKind; public var documentId: String?; public var pageNumber: Int?
  public var vendor: String; public var model: String?; public var status: RunStatus; public var error: String?; public var imageCount: Int
  public var startedAt: Date; public var finishedAt: Date; public var durationMs: Int
  public init(id: String, kind: RunKind, documentId: String?, pageNumber: Int?, vendor: String, model: String?, status: RunStatus,
              error: String?, imageCount: Int, startedAt: Date, finishedAt: Date, durationMs: Int) {
    self.id = id; self.kind = kind; self.documentId = documentId; self.pageNumber = pageNumber; self.vendor = vendor; self.model = model
    self.status = status; self.error = error; self.imageCount = imageCount; self.startedAt = startedAt; self.finishedAt = finishedAt
    self.durationMs = durationMs
  }
}
