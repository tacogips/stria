import Foundation

public enum DictationState: Equatable, Sendable {
  case idle, requestingPermission, preparing, recording(level: Float), transcribing, failed(message: String)

  public var isRecording: Bool { if case .recording = self { return true }; return false }
  public var isActive: Bool {
    switch self {
    case .idle, .failed: false
    default: true
    }
  }
}

public enum SpeechInputEvent: Sendable {
  case partial(String), final(String), level(Float), failed(String)
}

@MainActor
public protocol SpeechTranscriptionEngine: AnyObject {
  func requestPermission() async throws
  func start(language: String, onEvent: @escaping @MainActor @Sendable (SpeechInputEvent) -> Void) async throws
  func stop() async throws -> String
  func cancel()
}

public struct SpeechInputError: LocalizedError, Sendable, Equatable {
  public let message: String
  public init(_ message: String) { self.message = message }
  public var errorDescription: String? { message }
}
