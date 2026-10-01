import Foundation

public struct DocumentRecord: Codable, Equatable, Sendable {
  public var id: String; public var sha256: String; public var title: String; public var originalFilename: String
  public var originalPath: String; public var byteSize: Int64; public var pageCount: Int; public var importStatus: ImportStatus
  public var renderDPI: Int; public var imageFormat: ImageFormat; public var ocrVendor: String?; public var ocrModel: String?
  public var outlineJSON: String?; public var lastReadPage: Int?; public var lastOpenedAt: Date?; public var importedAt: Date; public var updatedAt: Date
  public init(id: String, sha256: String, title: String, originalFilename: String, originalPath: String, byteSize: Int64,
              pageCount: Int, importStatus: ImportStatus, renderDPI: Int, imageFormat: ImageFormat, ocrVendor: String? = nil,
              ocrModel: String? = nil, outlineJSON: String? = nil, lastReadPage: Int? = nil, lastOpenedAt: Date? = nil,
              importedAt: Date, updatedAt: Date) {
    self.id = id; self.sha256 = sha256; self.title = title; self.originalFilename = originalFilename; self.originalPath = originalPath
    self.byteSize = byteSize; self.pageCount = pageCount; self.importStatus = importStatus; self.renderDPI = renderDPI
    self.imageFormat = imageFormat; self.ocrVendor = ocrVendor; self.ocrModel = ocrModel; self.outlineJSON = outlineJSON
    self.lastReadPage = lastReadPage; self.lastOpenedAt = lastOpenedAt; self.importedAt = importedAt; self.updatedAt = updatedAt
  }
}

public struct OCRCounts: Codable, Equatable, Sendable {
  public var done: Int; public var failed: Int; public var pending: Int
  public init(done: Int, failed: Int, pending: Int) { self.done = done; self.failed = failed; self.pending = pending }
}

public struct DocumentSummary: Codable, Equatable, Sendable {
  public var id: String; public var title: String; public var pageCount: Int; public var importStatus: ImportStatus
  public var importedAt: Date; public var originalPath: String; public var ocr: OCRCounts
  public init(id: String, title: String, pageCount: Int, importStatus: ImportStatus, importedAt: Date, originalPath: String, ocr: OCRCounts) {
    self.id = id; self.title = title; self.pageCount = pageCount; self.importStatus = importStatus
    self.importedAt = importedAt; self.originalPath = originalPath; self.ocr = ocr
  }
}

public struct OutlineNode: Codable, Equatable, Sendable {
  public var title: String; public var page: Int?; public var children: [OutlineNode]
  public init(title: String, page: Int?, children: [OutlineNode] = []) { self.title = title; self.page = page; self.children = children }
  enum CodingKeys: String, CodingKey { case title, page, children }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    title = try c.decode(String.self, forKey: .title); page = try c.decodeIfPresent(Int.self, forKey: .page)
    children = try c.decodeIfPresent([OutlineNode].self, forKey: .children) ?? []
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(title, forKey: .title); try c.encode(page, forKey: .page); try c.encode(children, forKey: .children)
  }
}
