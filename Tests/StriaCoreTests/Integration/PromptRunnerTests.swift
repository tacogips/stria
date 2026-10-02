import AgentGateway
import AgentGatewayAppCore
import Foundation
@testable import StriaCore
import Testing

/// Records the gateway params it receives and answers with scripted text or a hang.
private actor FakeGatewayExecutor: GatewayExecuting {
  enum Behaviour { case reply(String), hang }
  let behaviour: Behaviour
  private(set) var params: [GatewayExecuteParams] = []

  init(_ behaviour: Behaviour) { self.behaviour = behaviour }

  func execute(_ params: GatewayExecuteParams, emit: @escaping GatewayEventEmitter) async throws -> GatewayExecuteResult {
    self.params.append(params)
    switch behaviour {
    case .reply(let text):
      return GatewayExecuteResult(vendor: params.vendor, model: params.model, text: text)
    case .hang:
      try await Task.sleep(for: .seconds(60))
      return GatewayExecuteResult(vendor: params.vendor, model: params.model, text: "late")
    }
  }
}

private func writePNG(at url: URL) throws {
  try url.deletingLastPathComponent().createDirectoryIfNeeded()
  let image = try askStoredImage()
  try ImageCodec.pngData(ImageCodec.decode(image.data)).write(to: url)
}

private extension URL {
  func createDirectoryIfNeeded() throws {
    try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
  }
}

@Suite("PromptRunnerTests") struct PromptRunnerTests {
  @Test func apiVendorReceivesImageBlocksAndResultText() async throws {
    try await withTestDataRoot { paths in
      let png = paths.cache.appendingPathComponent("page.png")
      try writePNG(at: png)
      let executor = FakeGatewayExecutor(.reply("final text"))
      let runner = GatewayPromptRunner(makeExecutor: { _ in executor })
      let settings = ServiceSettings(vendor: "anthropic", model: "m", apiKeyEnvironment: nil, timeoutSeconds: 30)
      let text = try await runner.run(settings: settings, systemPrompt: "sys", parts: [.text("prompt"), .image(png)],
                                      cwd: paths.cache, environment: [:], secretValue: nil)
      #expect(text == "final text")
      let params = await executor.params
      #expect(params.count == 1)
      #expect(params.first?.images.count == 1)
      #expect(params.first?.prompt == "prompt")
      #expect(params.first?.systemPrompt == "sys")
    }
  }

  @Test func cliVendorReceivesImagePathInPromptAndNoImages() async throws {
    try await withTestDataRoot { paths in
      let png = paths.cache.appendingPathComponent("page.png")
      try writePNG(at: png)
      let executor = FakeGatewayExecutor(.reply("ok"))
      let runner = GatewayPromptRunner(makeExecutor: { _ in executor })
      let settings = ServiceSettings(vendor: "claude-code", model: "m", apiKeyEnvironment: nil, timeoutSeconds: 30)
      _ = try await runner.run(settings: settings, systemPrompt: nil, parts: [.text("prompt"), .image(png)],
                               cwd: paths.cache, environment: [:], secretValue: nil)
      let params = await executor.params
      #expect(params.first?.images.isEmpty == true)
      #expect(params.first?.prompt.contains(png.path) == true)
      #expect(params.first?.workingDirectory == paths.cache.path)
    }
  }

  @Test func hungVendorTimesOutAsFailed() async throws {
    try await withTestDataRoot { paths in
      let executor = FakeGatewayExecutor(.hang)
      let runner = GatewayPromptRunner(makeExecutor: { _ in executor })
      let settings = ServiceSettings(vendor: "anthropic", model: "m", apiKeyEnvironment: nil, timeoutSeconds: 1)
      let started = Date()
      await #expect(throws: ServiceError.failed("timed out after 1 s")) {
        try await runner.run(settings: settings, systemPrompt: nil, parts: [.text("prompt")],
                             cwd: paths.cache, environment: [:], secretValue: nil)
      }
      #expect(Date().timeIntervalSince(started) < 10)
    }
  }

  @Test func cancellationStopsTheCall() async throws {
    try await withTestDataRoot { paths in
      let executor = FakeGatewayExecutor(.hang)
      let runner = GatewayPromptRunner(makeExecutor: { _ in executor })
      let settings = ServiceSettings(vendor: "anthropic", model: "m", apiKeyEnvironment: nil, timeoutSeconds: 60)
      let task = Task {
        try await runner.run(settings: settings, systemPrompt: nil, parts: [.text("prompt")],
                             cwd: paths.cache, environment: [:], secretValue: nil)
      }
      try await Task.sleep(for: .milliseconds(200))
      task.cancel()
      let started = Date()
      await #expect(throws: CancellationError.self) { try await task.value }
      #expect(Date().timeIntervalSince(started) < 10)
    }
  }

  @Test func noTextSentinelBecomesEmptyDoneText() async throws {
    try await withTestDataRoot { paths in
      let png = paths.cache.appendingPathComponent("page.png")
      try writePNG(at: png)
      let executor = FakeGatewayExecutor(.reply("```\n[NO TEXT]\n```"))
      let service = GatewayOCRService(paths: paths, environment: [:], runner: GatewayPromptRunner(makeExecutor: { _ in executor }))
      let request = OCRRequest(docId: "doc", page: 1, pngPath: png, prompt: OCRDefaults.prompt,
                               settings: ServiceSettings(vendor: "claude-code", model: "m", apiKeyEnvironment: nil))
      #expect(try await service.recognize(request).text == "")
      #expect(OCRDefaults.prompt.contains(OCRDefaults.noTextSentinel))
    }
  }
}
