import Foundation

public struct SyncCounts: Codable, Equatable, Sendable {
  public var pushed = 0
  public var pulled = 0
  public init(pushed: Int = 0, pulled: Int = 0) { self.pushed = pushed; self.pulled = pulled }
}

public struct SyncReport: Codable, Equatable, Sendable {
  public var documents = SyncCounts()
  public var ocr = SyncCounts()
  public var summaries = SyncCounts()
  public var chats = SyncCounts()
  public var pending = 0
  public var errors: [String] = []
  public var folder: String
  public init(folder: String) { self.folder = folder }
}

struct SyncFormat: Codable { let version: Int }
struct SyncTombstone: Codable { let deletedAt: Date }

struct SyncDocument: Codable {
  let docId: String
  let sha256: String
  let title: String
  let originalFilename: String
  let byteSize: Int64
  let pageCount: Int
  let importedAt: Date
  let updatedAt: Date
  let outline: [OutlineNode]?

  init(_ record: DocumentRecord) throws {
    docId = record.id; sha256 = record.sha256; title = record.title; originalFilename = record.originalFilename
    byteSize = record.byteSize; pageCount = record.pageCount; importedAt = record.importedAt; updatedAt = record.updatedAt
    outline = try record.outlineJSON.map { try JSONDecoder().decode([OutlineNode].self, from: Data($0.utf8)) }
  }
}

struct SyncOCR: Codable {
  let page: Int
  let status: OCRStatus
  let text: String?
  let tags: [String]
  let error: String?
  let vendor: String?
  let model: String?
  let updatedAt: Date

  init?(_ info: PageInfo) {
    guard info.ocrStatus != .pending, let updated = info.ocrUpdatedAt else { return nil }
    page = info.pageNumber; status = info.ocrStatus; text = info.ocrText; tags = info.ocrTags
    error = info.ocrError; vendor = info.ocrVendor; model = info.ocrModel; updatedAt = updated
  }
}

struct SyncSummary: Codable {
  let record: PageSummaryRecord
  let sourceOCRUpdatedAt: Date?

  // Flatten the record's fields in the wire format.
  enum CodingKeys: String, CodingKey {
    case documentId, pageNumber, status, summary, error, language, instruction, vendor, model, isStale, updatedAt, sourceOCRUpdatedAt
  }
  init(record: PageSummaryRecord, sourceOCRUpdatedAt: Date?) { self.record = record; self.sourceOCRUpdatedAt = sourceOCRUpdatedAt }
  init(from decoder: Decoder) throws {
    record = try PageSummaryRecord(from: decoder)
    let c = try decoder.container(keyedBy: CodingKeys.self)
    sourceOCRUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .sourceOCRUpdatedAt)
  }
  func encode(to encoder: Encoder) throws {
    try record.encode(to: encoder)
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(sourceOCRUpdatedAt, forKey: .sourceOCRUpdatedAt)
  }
}

struct SyncMessage: Codable {
  let role: ChatRole
  let status: MessageStatus
  let content: String
  let documentId: String?
  let page: Int?
  let vendor: String?
  let model: String?
  let citations: [PageRef]
  let createdAt: Date
  init(_ message: ChatMessageRecord) {
    role = message.role; status = message.status; content = message.content; documentId = message.documentId
    page = message.pageNumber; vendor = message.vendor; model = message.model; citations = message.citations; createdAt = message.createdAt
  }
}

struct SyncThread: Codable {
  let id: String
  let documentId: String?
  let pageNumber: Int?
  let scope: ChatScope
  let title: String?
  let summary: String?
  let summaryThroughIndex: Int?
  let createdAt: Date
  let updatedAt: Date
  let messages: [SyncMessage]
}
