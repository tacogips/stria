import Foundation
import PDFKit

public struct PDFTextLayerOCRService: OCRService {
  private let paths: StriaPaths

  public init(paths: StriaPaths) {
    self.paths = paths
  }

  public func recognize(_ request: OCRRequest) async throws -> OCRResult {
    guard let document = PDFDocument(url: paths.original(docId: request.docId)),
          let page = document.page(at: request.page - 1) else {
      throw ServiceError.failed("page not available")
    }
    return OCRResult(text: (page.string ?? "").precomposedStringWithCompatibilityMapping)
  }
}
