import Foundation
import StriaCore

public func withTestDataRoot<T>(_ body: (StriaPaths) async throws -> T) async throws -> T {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("stria-tests-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  return try await body(StriaPaths(root: root))
}

public extension StriaConfig {
  /// Defaults plus configured (fake-friendly) vendors, so coordinators do
  /// not short-circuit as "not configured" in tests that use the fakes.
  static var testing: StriaConfig {
    var config = StriaConfig.defaults
    config.ocr.vendor = "anthropic"
    config.ocr.model = "test-ocr-model"
    config.ocr.apiKeyEnvironment = "TEST_API_KEY"
    // A CLI vendor needs no key, so app-model tests can send without one.
    config.agent.vendor = "claude-code"
    config.agent.model = "test-agent-model"
    // Background summaries would add agent calls to tests that count them.
    config.agent.autoSummarize = false
    return config
  }
}

public func makeTestEnvironment(
  paths: StriaPaths,
  ocr: any OCRService = FakeOCRService(),
  agent: any AgentService = FakeAgentService(),
  config: StriaConfig = .testing,
  clock: @escaping @Sendable () -> Date = { Date() }
) -> StriaEnvironment {
  StriaEnvironment(paths: paths, config: config, ocrService: ocr, agentService: agent, clock: clock,
                    ocrRetryDelay: { _ in .zero })
}
