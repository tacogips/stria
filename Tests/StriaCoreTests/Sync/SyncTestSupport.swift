import Foundation
@testable import StriaCore

struct SyncFixture {
  let a: StriaLibrary
  let b: StriaLibrary
  let folder: URL
  let source: URL
  let ocrA: FakeOCRService
  let ocrB: FakeOCRService
  let agent: FakeAgentService

  static func make(_ paths: StriaPaths, forceLike: Bool = false) throws -> Self {
    let folder = paths.root.appendingPathComponent("shared")
    let source = paths.root.appendingPathComponent("sample.pdf")
    try SamplePDFFactory.makePDF(at: source, pages: ["sample page", "second page"])
    let ocrA = FakeOCRService(), ocrB = FakeOCRService(), agent = FakeAgentService()
    var config = StriaConfig.testing
    config.summary.vendor = "claude-code"; config.summary.model = "test-model"
    config.sync.enabled = true
    let resolver = SyncFolder(environment: [:], platform: .iOS, provider: { .init(url: folder) })
    func library(_ name: String, ocr: FakeOCRService, time: TimeInterval) throws -> StriaLibrary {
      let environment = StriaEnvironment(paths: StriaPaths(root: paths.root.appendingPathComponent(name)), config: config,
                                         ocrService: ocr, agentService: agent, clock: { Date(timeIntervalSince1970: time) },
                                         ocrRetryDelay: { _ in .zero }, syncFolder: resolver, syncFileCoordinator: LocalSyncFileCoordinator())
      return try StriaLibrary.open(environment: environment, storeOptions: .init(forceLikeSearch: forceLike))
    }
    return try Self(a: library("A", ocr: ocrA, time: 1000), b: library("B", ocr: ocrB, time: 2000),
                    folder: folder, source: source, ocrA: ocrA, ocrB: ocrB, agent: agent)
  }
}

/// The test sandbox cannot contact filecoordinationd. Production always uses
/// SystemSyncFileCoordinator; this adapter exercises the same file operations.
struct LocalSyncFileCoordinator: SyncFileCoordinating {
  func coordinate(_ url: URL, writing: Bool, accessor: (URL) throws -> Void) throws { try accessor(url) }
}
