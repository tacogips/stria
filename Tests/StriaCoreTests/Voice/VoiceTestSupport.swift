import Foundation
import StriaCore
import Testing

@MainActor
final class FakeSpeechEngine: SpeechTranscriptionEngine {
  var events: (@MainActor @Sendable (SpeechInputEvent) -> Void)?
  var starts = 0
  var stops = 0
  var cancels = 0
  var text = "final words"
  var failure: SpeechInputError?
  var permissionGate: VoiceTestTicks?
  var startGate: VoiceTestTicks?
  var permissionFailure: SpeechInputError?
  var language: String?

  func requestPermission() async throws {
    if let permissionGate { try await permissionGate.sleep() }
    if let permissionFailure { throw permissionFailure }
  }
  func start(language: String, onEvent: @escaping @MainActor @Sendable (SpeechInputEvent) -> Void) async throws {
    starts += 1; self.language = language; events = onEvent
    if let startGate { try await startGate.sleep() }
  }
  func stop() async throws -> String { stops += 1; if let failure { throw failure }; return text }
  func cancel() { cancels += 1 }
}

@MainActor
final class VoiceComposerFixture {
  var input = "Typed question"
  var notice: String?
  var submits = 0
  var config = StriaConfig.VoiceConfig()
  let engine = FakeSpeechEngine()
  lazy var controller = SpeechInputController(config: { self.config }, makeEngine: { _ in self.engine },
    readInput: { self.input }, writeInput: { self.input = $0 }, notice: { self.notice = $0 }, submit: { self.submits += 1 })
}

@MainActor
func waitForVoice(_ predicate: @MainActor () -> Bool) async throws {
  let deadline = ContinuousClock.now + .seconds(3)
  while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
  try #require(predicate())
}

actor VoiceTestTicks {
  private var continuation: CheckedContinuation<Void, any Error>?
  var waiting: Bool { continuation != nil }
  func sleep() async throws { try await withCheckedThrowingContinuation { continuation = $0 } }
  func tick() { continuation?.resume(); continuation = nil }
}
