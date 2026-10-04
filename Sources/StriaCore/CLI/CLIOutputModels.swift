import Foundation

public struct ImportOutput: Encodable {
  public let alreadyImported: Bool
  public let document: DocumentSummary
  public let ocr: ImportOCROutput
}

public struct ImportOCROutput: Encodable {
  public let status: ImportOCRStatus
  public let reason: String?
  public let done: Int
  public let failed: Int
  public let pending: Int

  enum CodingKeys: String, CodingKey { case status, reason, done, failed, pending }

  public init(_ value: ImportOCROutcome) {
    status = value.status
    reason = value.reason
    done = value.done
    failed = value.failed
    pending = value.pending
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(status, forKey: .status)
    try container.encode(reason, forKey: .reason)
    try container.encode(done, forKey: .done)
    try container.encode(failed, forKey: .failed)
    try container.encode(pending, forKey: .pending)
  }
}

public struct OCROutput: Encodable {
  public let docId: String
  public let processed: [Int]
  public let done: Int
  public let failed: Int
  public let pending: Int
  public let failures: [OCRFailure]

  public init(_ result: OCRRunSummary) {
    docId = result.docId
    processed = result.processed
    done = result.done
    failed = result.failed
    pending = result.pending
    failures = result.failures
  }
}

public struct ListOutput: Encodable { public let documents: [DocumentSummary] }

public struct RemoveOutput: Encodable {
  public let docId: String
  public let removed: Bool
}

public struct ShowDocumentOutput: Encodable {
  public let id: String
  public let title: String
  public let pageCount: Int
  public let importStatus: ImportStatus
  public let importedAt: Date
  public let originalPath: String
  public let ocr: OCRCounts
  public let sha256: String
  public let byteSize: Int64
  public let renderDpi: Int
  public let imageFormat: ImageFormat
  public let ocrVendor: String?
  public let ocrModel: String?

  enum CodingKeys: String, CodingKey {
    case id, title, pageCount, importStatus, importedAt, originalPath, ocr, sha256, byteSize, renderDpi, imageFormat, ocrVendor, ocrModel
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(pageCount, forKey: .pageCount)
    try container.encode(importStatus, forKey: .importStatus)
    try container.encode(importedAt, forKey: .importedAt)
    try container.encode(originalPath, forKey: .originalPath)
    try container.encode(ocr, forKey: .ocr)
    try container.encode(sha256, forKey: .sha256)
    try container.encode(byteSize, forKey: .byteSize)
    try container.encode(renderDpi, forKey: .renderDpi)
    try container.encode(imageFormat, forKey: .imageFormat)
    try container.encode(ocrVendor, forKey: .ocrVendor)
    try container.encode(ocrModel, forKey: .ocrModel)
  }
}

public struct ShowOutput: Encodable {
  public let document: ShowDocumentOutput
  public let outline: [OutlineNode]
}

public struct PageImageOutput: Encodable {
  public let docId: String
  public let page: Int
  public let path: String
  public let width: Int
  public let height: Int
  public let format: String
  public let cached: Bool
}

public struct PageTextOutput: Encodable {
  public let docId: String
  public let page: Int
  public let ocrStatus: OCRStatus
  public let text: String?
  public let ocrError: String?
  public let ocrVendor: String?
  public let ocrModel: String?

  enum CodingKeys: String, CodingKey { case docId, page, ocrStatus, text, ocrError, ocrVendor, ocrModel }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(docId, forKey: .docId)
    try container.encode(page, forKey: .page)
    try container.encode(ocrStatus, forKey: .ocrStatus)
    try container.encode(text, forKey: .text)
    try container.encode(ocrError, forKey: .ocrError)
    try container.encode(ocrVendor, forKey: .ocrVendor)
    try container.encode(ocrModel, forKey: .ocrModel)
  }
}

public struct SearchOutput: Encodable {
  public struct Result: Encodable {
    public let docId: String
    public let title: String
    public let page: Int
    public let snippet: String
    public let score: Double
    public let imagePath: String
    public let imageCached: Bool
  }
  public let query: String
  public let matchMode: MatchMode
  public let results: [Result]
}

public struct AskOutput: Encodable {
  public struct OutputCitation: Encodable {
    public let docId: String
    public let title: String
    public let page: Int
    public let imagePath: String
  }
  public let threadId: String
  public let answer: String
  public let vendor: String
  public let model: String?
  public let runId: String
  public let citations: [OutputCitation]
  public let contextPages: [OutputCitation]

  enum CodingKeys: String, CodingKey { case threadId, answer, vendor, model, runId, citations, contextPages }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(threadId, forKey: .threadId)
    try container.encode(answer, forKey: .answer)
    try container.encode(vendor, forKey: .vendor)
    try container.encode(model, forKey: .model)
    try container.encode(runId, forKey: .runId)
    try container.encode(citations, forKey: .citations)
    try container.encode(contextPages, forKey: .contextPages)
  }
}

public struct HistoryCitationOutput: Encodable {
  public let docId: String
  public let page: Int
}

public struct HistoryMessageOutput: Encodable {
  public let id: Int64
  public let threadId: String
  public let role: ChatRole
  public let status: MessageStatus
  public let content: String
  public let docId: String?
  public let page: Int?
  public let vendor: String?
  public let model: String?
  public let runId: String?
  public let citations: [HistoryCitationOutput]
  public let createdAt: Date

  enum CodingKeys: String, CodingKey { case id, threadId, role, status, content, docId, page, vendor, model, runId, citations, createdAt }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(threadId, forKey: .threadId)
    try container.encode(role, forKey: .role)
    try container.encode(status, forKey: .status)
    try container.encode(content, forKey: .content)
    try container.encode(docId, forKey: .docId)
    try container.encode(page, forKey: .page)
    try container.encode(vendor, forKey: .vendor)
    try container.encode(model, forKey: .model)
    try container.encode(runId, forKey: .runId)
    try container.encode(citations, forKey: .citations)
    try container.encode(createdAt, forKey: .createdAt)
  }
}

public struct HistoryOutput: Encodable {
  public let messages: [HistoryMessageOutput]
}

public struct ConfigValueOutput: Encodable { public let key: String; public let value: JSONValue }
public struct PathsOutput: Encodable {
  public let home: String
  public let database: String
  public let originals: String
  public let cache: String
  public let config: String
  public let logs: String
}

/// One conversation in `stria history --threads`.
public struct ThreadOutput: Encodable {
  public let threadId: String
  public let docId: String?
  public let page: Int?
  public let title: String?
  public let firstQuestion: String
  public let summary: String?
  public let summaryCurrent: Bool
  public let messageCount: Int
  public let updatedAt: Date

  enum CodingKeys: String, CodingKey { case threadId, docId, page, title, firstQuestion, summary, summaryCurrent, messageCount, updatedAt }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(threadId, forKey: .threadId)
    try container.encode(docId, forKey: .docId)
    try container.encode(page, forKey: .page)
    try container.encode(title, forKey: .title)
    try container.encode(firstQuestion, forKey: .firstQuestion)
    try container.encode(summary, forKey: .summary)
    try container.encode(summaryCurrent, forKey: .summaryCurrent)
    try container.encode(messageCount, forKey: .messageCount)
    try container.encode(updatedAt, forKey: .updatedAt)
  }
}

/// `stria history --threads`: one entry per conversation with its summary.
public struct ThreadsOutput: Encodable {
  public let threads: [ThreadOutput]
}
