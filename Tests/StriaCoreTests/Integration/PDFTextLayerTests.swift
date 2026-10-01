import Foundation
import StriaCore
import Testing

struct PDFTextLayerTests {
  @Test func extractsTextFromOriginalPDF() async throws {
    try await withTestDataRoot { paths in
      try FileManager.default.createDirectory(at: paths.originals, withIntermediateDirectories: true)
      try SamplePDFFactory.makePDF(at: paths.original(docId: "d1"), pages: ["first sample", "page two sample"])
      let request = OCRRequest(docId: "d1", page: 2, pngPath: paths.cachedPage(docId: "d1", page: 2), prompt: "ignored", settings: .init(vendor: "pdf-text-layer", model: nil, apiKeyEnvironment: nil))
      let result = try await PDFTextLayerOCRService(paths: paths).recognize(request)
      #expect(result.text.contains("page two sample"))
    }
  }

  @Test func missingDocumentThrowsServiceFailure() async throws {
    try await withTestDataRoot { paths in
      let request = OCRRequest(docId: "missing", page: 1, pngPath: URL(fileURLWithPath: "/unused"), prompt: "", settings: .init(vendor: "pdf-text-layer", model: nil, apiKeyEnvironment: nil))
      await #expect(throws: ServiceError.failed("page not available")) {
        try await PDFTextLayerOCRService(paths: paths).recognize(request)
      }
    }
  }
}
