import AgentGateway
import AgentGatewayAppCore
import Foundation
@testable import StriaCore
import Testing

private final class EnvironmentRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [[String: String]] = []

  func append(_ environment: [String: String]) {
    lock.lock(); defer { lock.unlock() }
    values.append(environment)
  }

  var environments: [[String: String]] {
    lock.lock(); defer { lock.unlock() }
    return values
  }
}

private actor MobileGatewayExecutor: GatewayExecuting {
  private(set) var calls = 0

  func execute(_ params: GatewayExecuteParams, emit: @escaping GatewayEventEmitter) async throws -> GatewayExecuteResult {
    calls += 1
    return GatewayExecuteResult(vendor: params.vendor, model: params.model, text: "answer")
  }
}

@Suite("MobileCredentialTests") struct MobileCredentialTests {
  @Test func gatewayReadsChangedKeyAndVariableNameOnNextCall() async throws {
    try await withTestDataRoot { paths in
      let store = InMemoryCredentialStore()
      let recorder = EnvironmentRecorder()
      let executor = MobileGatewayExecutor()
      let runner = GatewayPromptRunner(makeExecutor: { environment in
        recorder.append(environment)
        return executor
      })
      let service = GatewayAgentService(paths: paths, environment: ["PATH": "/bin"], runner: runner,
                                        platform: .iOS, credentialStore: store)
      store.write("first", vendor: "openai")
      var request = AgentRequest(question: "hello", systemPrompt: "system", contextPages: [], history: [],
                                  settings: ServiceSettings(vendor: "openai", model: "m", apiKeyEnvironment: "CUSTOM_KEY"))
      _ = try await service.ask(request)
      store.write("second", vendor: "openai")
      request.settings.apiKeyEnvironment = "CHANGED_KEY"
      _ = try await service.ask(request)
      #expect(recorder.environments == [["PATH": "/bin", "CUSTOM_KEY": "first"], ["PATH": "/bin", "CHANGED_KEY": "second"]])
      store.delete(vendor: "openai")
      await #expect(throws: ServiceError.unavailable("environment variable CHANGED_KEY is not set")) {
        try await service.ask(request)
      }
      #expect(await executor.calls == 2)
    }
  }

  @Test func gatewayBlocksMobileCLIAtPreflight() async throws {
    try await withTestDataRoot { paths in
      let recorder = EnvironmentRecorder()
      let executor = MobileGatewayExecutor()
      let runner = GatewayPromptRunner(makeExecutor: { environment in
        recorder.append(environment)
        return executor
      })
      let service = GatewayAgentService(paths: paths, environment: [:], runner: runner, platform: .iOS)
      let request = AgentRequest(question: "hello", systemPrompt: "", contextPages: [], history: [],
                                  settings: ServiceSettings(vendor: "codex", model: nil, apiKeyEnvironment: nil))
      await #expect(throws: ServiceError.unavailable(KnownVendors.platformUnavailableReason)) {
        try await service.ask(request)
      }
      #expect(recorder.environments.isEmpty)
      #expect(await executor.calls == 0)
    }
  }
}
