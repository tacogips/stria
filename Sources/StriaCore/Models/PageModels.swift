import Foundation

public struct PageInfo: Codable, Equatable, Sendable {
  public var documentId: String; public var pageNumber: Int; public var imageFormat: ImageFormat; public var width: Int; public var height: Int
  public var ocrStatus: OCRStatus; public var ocrText: String?; public var ocrVendor: String?; public var ocrModel: String?
  public var ocrError: String?; public var ocrAttempts: Int; public var ocrUpdatedAt: Date?
  public init(documentId: String, pageNumber: Int, imageFormat: ImageFormat, width: Int, height: Int, ocrStatus: OCRStatus,
              ocrText: String? = nil, ocrVendor: String? = nil, ocrModel: String? = nil, ocrError: String? = nil,
              ocrAttempts: Int = 0, ocrUpdatedAt: Date? = nil) {
    self.documentId = documentId; self.pageNumber = pageNumber; self.imageFormat = imageFormat; self.width = width; self.height = height
    self.ocrStatus = ocrStatus; self.ocrText = ocrText; self.ocrVendor = ocrVendor; self.ocrModel = ocrModel
    self.ocrError = ocrError; self.ocrAttempts = ocrAttempts; self.ocrUpdatedAt = ocrUpdatedAt
  }
}
public struct StoredPageImage: Equatable, Sendable {
  public var data: Data; public var format: ImageFormat; public var width: Int; public var height: Int
  public init(data: Data, format: ImageFormat, width: Int, height: Int) { self.data = data; self.format = format; self.width = width; self.height = height }
}
public struct PageRef: Codable, Hashable, Sendable {
  public var docId: String; public var page: Int
  public init(docId: String, page: Int) { self.docId = docId; self.page = page }
}
