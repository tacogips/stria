import Foundation
import StriaCore

public func withTestDataRoot<T>(_ body: (StriaPaths) async throws -> T) async throws -> T {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("stria-tests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  return try await body(StriaPaths(root: root))
}

public func makeTestEnvironment(
  paths: StriaPaths,
  ocr: any OCRService = FakeOCRService(),
  agent: any AgentService = FakeAgentService(),
  config: StriaConfig = .defaults,
  clock: @escaping @Sendable () -> Date = { Date() }
) -> StriaEnvironment {
  StriaEnvironment(paths: paths, config: config, ocrService: ocr, agentService: agent, clock: clock)
}
