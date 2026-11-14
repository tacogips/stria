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

  @Test func compatibilityNormalizesLigatures() async throws {
    try await withTestDataRoot { paths in
      try FileManager.default.createDirectory(at: paths.originals, withIntermediateDirectories: true)
      try SamplePDFFactory.makePDF(at: paths.original(docId: "d1"), pages: ["offline efficient fluffy"])
      let request = OCRRequest(docId: "d1", page: 1, pngPath: paths.cachedPage(docId: "d1", page: 1), prompt: "ignored", settings: .init(vendor: "pdf-text-layer", model: nil, apiKeyEnvironment: nil))

      let result = try await PDFTextLayerOCRService(paths: paths).recognize(request)

      #expect(result.text.contains("offline"))
      #expect(result.text.contains("efficient"))
      #expect(result.text.contains("fluffy"))
      #expect(result.text.unicodeScalars.allSatisfy { !(0xFB00...0xFB06).contains(Int($0.value)) })
    }
  }

  @Test func missingPageThrowsServiceFailure() async throws {
    try await withTestDataRoot { paths in
      try FileManager.default.createDirectory(at: paths.originals, withIntermediateDirectories: true)
      try SamplePDFFactory.makePDF(at: paths.original(docId: "d1"), pages: ["first", "second"])
      let request = OCRRequest(docId: "d1", page: 99, pngPath: paths.cachedPage(docId: "d1", page: 99), prompt: "ignored", settings: .init(vendor: "pdf-text-layer", model: nil, apiKeyEnvironment: nil))

      await #expect(throws: ServiceError.failed("page not available")) {
        try await PDFTextLayerOCRService(paths: paths).recognize(request)
      }
    }
  }

  @Test func blankPageReturnsEmptyText() async throws {
    try await withTestDataRoot { paths in
      try FileManager.default.createDirectory(at: paths.originals, withIntermediateDirectories: true)
      try SamplePDFFactory.makePDF(at: paths.original(docId: "d1"), pages: [""])
      let request = OCRRequest(docId: "d1", page: 1, pngPath: paths.cachedPage(docId: "d1", page: 1), prompt: "ignored", settings: .init(vendor: "pdf-text-layer", model: nil, apiKeyEnvironment: nil))

      let result = try await PDFTextLayerOCRService(paths: paths).recognize(request)

      #expect(result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  }
}
