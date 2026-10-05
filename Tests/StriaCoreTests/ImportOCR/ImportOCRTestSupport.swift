import Foundation
import StriaCore

func makeImportFixture(paths: StriaPaths, pageTexts: [String], ocr: FakeOCRService = FakeOCRService(),
                       onRunLogFailure: (@Sendable (String) -> Void)? = nil) async throws -> (StriaLibrary, URL) {
  let source = paths.root.appendingPathComponent("fixture.pdf")
  try SamplePDFFactory.makePDF(at: source, pages: pageTexts)
  let environment = StriaEnvironment(paths: paths, config: .testing, ocrService: ocr, agentService: FakeAgentService(),
                                     onRunLogFailure: onRunLogFailure, ocrRetryDelay: { _ in .zero })
  return (try StriaLibrary.open(environment: environment), source)
}

func importFixture(_ library: StriaLibrary, source: URL, runOCR: Bool = false) async throws -> ImportResult {
  try await library.importDocument(at: source, runOCR: runOCR)
}
