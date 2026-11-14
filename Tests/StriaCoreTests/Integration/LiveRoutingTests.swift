import Foundation
@testable import StriaCore
import Testing

struct LiveRoutingTests {
  @Test func routesPDFTextLayerOffline() async throws {
    try await withTestDataRoot { paths in
      try FileManager.default.createDirectory(at: paths.originals, withIntermediateDirectories: true)
      try SamplePDFFactory.makePDF(at: paths.original(docId: "d1"), pages: ["offline text"])
      let request = OCRRequest(docId: "d1", page: 1, pngPath: URL(fileURLWithPath: "/unused"), prompt: "", settings: .init(vendor: "pdf-text-layer", model: nil, apiKeyEnvironment: nil))
      let result = try await LiveOCRService(paths: paths, environment: [:]).recognize(request)
      #expect(result.text.contains("offline text"))
    }
  }

  @Test func rejectsCursorAPIBeforeAnyGatewayCall() async throws {
    try await withTestDataRoot { paths in
      let request = OCRRequest(docId: "d1", page: 1, pngPath: URL(fileURLWithPath: "/missing"), prompt: "", settings: .init(vendor: "cursor-api", model: "m", apiKeyEnvironment: "KEY"))
      await #expect(throws: ServiceError.unavailable("vendor cursor-api does not support image input")) {
        try await LiveOCRService(paths: paths, environment: ["KEY": "x"]).recognize(request)
      }
    }
  }

  @Test func liveFactoryKeepsPathsAndConfig() async throws {
    try await withTestDataRoot { paths in
      let config = StriaConfig.defaults
      let live = StriaEnvironment.live(paths: paths, config: config, environment: [:])
      #expect(live.paths == paths)
      #expect(live.config == config)
    }
  }
}
