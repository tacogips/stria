import Foundation
import StriaCore

final class AppModelTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var tick = 0

  func now() -> Date {
    lock.lock()
    defer { lock.unlock() }
    tick += 1
    return Date(timeIntervalSince1970: TimeInterval(tick))
  }
}

@MainActor
func withAppModelDataRoot<T>(_ body: (StriaPaths) async throws -> T) async throws -> T {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("stria-app-model-tests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  return try await body(StriaPaths(root: root))
}

func makeAppModelFixture(
  paths: StriaPaths,
  pageTexts: [String],
  filename: String = "fixture.pdf",
  ocr: FakeOCRService = FakeOCRService(),
  agent: FakeAgentService = FakeAgentService(),
  config: StriaConfig = .defaults,
  clock: @escaping @Sendable () -> Date = { Date() }
) throws -> (StriaLibrary, URL) {
  let source = paths.root.appendingPathComponent(filename)
  try SamplePDFFactory.makePDF(at: source, pages: pageTexts)
  let environment = makeTestEnvironment(paths: paths, ocr: ocr, agent: agent, config: config, clock: clock)
  return (try StriaLibrary.open(environment: environment), source)
}
