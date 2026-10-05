@preconcurrency import AVFoundation
@preconcurrency import Speech
import Foundation

@MainActor
public final class AppleSpeechEngine: SpeechTranscriptionEngine {
  private var implementation: (any SpeechTranscriptionEngine)?
  public init() {}

  public func requestPermission() async throws {
    try await VoicePermissions.microphone()
    let status = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization(Self.makeAuthorizationHandler(continuation))
    }
    guard status == .authorized else {
      throw SpeechInputError("Speech recognition access was denied. Enable Stria in Settings > Privacy & Security > Speech Recognition (System Settings on Mac).")
    }
  }

  nonisolated static func makeAuthorizationHandler(
    _ continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>
  ) -> (SFSpeechRecognizerAuthorizationStatus) -> Void {
    { continuation.resume(returning: $0) }
  }

  public func start(language: String, onEvent: @escaping @MainActor @Sendable (SpeechInputEvent) -> Void) async throws {
    let engine: any SpeechTranscriptionEngine
    if #available(macOS 26, iOS 26, *), SpeechTranscriber.isAvailable {
      engine = AnalyzerSpeechEngine()
    } else {
      engine = LegacyAppleSpeechEngine()
    }
    implementation = engine
    do { try await engine.start(language: language, onEvent: onEvent) } catch { engine.cancel(); throw error }
  }

  public func stop() async throws -> String {
    guard let implementation else { return "" }
    return try await implementation.stop()
  }

  public func cancel() { implementation?.cancel(); implementation = nil }
}

/// Older OS fallback: require on-device recognition wherever the locale
/// supports it. Settings explicitly describes Apple's server fallback.
@MainActor
final class LegacyAppleSpeechEngine: SpeechTranscriptionEngine {
  private let audio = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var recognition: SFSpeechRecognitionTask?
  private var tapped = false
  private var latestText = ""
  private var completion: CheckedContinuation<String, any Error>?
  private var timeout: Task<Void, Never>?
  private var stopped = false

  func requestPermission() async throws {}

  func start(language: String, onEvent: @escaping @MainActor @Sendable (SpeechInputEvent) -> Void) async throws {
    let locale = language == "auto" ? Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier) : Locale(identifier: language)
    guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
      throw SpeechInputError("Apple speech recognition is unavailable for this language.")
    }
    try VoiceAudioSession.activate()
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
    self.request = request
    recognition = recognizer.recognitionTask(with: request, resultHandler: Self.makeRecognitionHandler { [weak self] text, final, message in
      self?.receive(text: text, final: final, message: message, onEvent: onEvent)
    })
    let format = audio.inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechInputError("No microphone is available.") }
    audio.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(request: request, onEvent: onEvent))
    tapped = true
    audio.prepare()
    try audio.start()
  }

  // Framework callbacks run on arbitrary queues. Construct them outside actor
  // isolation and transfer only Sendable snapshots to the main actor.
  nonisolated static func makeRecognitionHandler(
    onResult: @escaping @MainActor @Sendable (String?, Bool, String?) -> Void
  ) -> (SFSpeechRecognitionResult?, (any Error)?) -> Void {
    { result, error in
      let text = result?.bestTranscription.formattedString
      let final = result?.isFinal == true
      let message = error?.localizedDescription
      Task { @MainActor in onResult(text, final, message) }
    }
  }

  nonisolated static func makeTap(
    request: SFSpeechAudioBufferRecognitionRequest,
    onEvent: @escaping @MainActor @Sendable (SpeechInputEvent) -> Void
  ) -> AVAudioNodeTapBlock {
    let sink = LegacySpeechAudioSink(request)
    return { buffer, _ in
      sink.append(buffer)
      let level = VoiceAudioLevel.measure(buffer)
      Task { @MainActor in onEvent(.level(level)) }
    }
  }

  private func receive(
    text: String?, final: Bool, message: String?,
    onEvent: @MainActor @Sendable (SpeechInputEvent) -> Void
  ) {
    guard !stopped else { return }
    if let text {
      latestText = text
      if final {
        if let completion {
          self.completion = nil; timeout?.cancel()
          completion.resume(returning: text)
        } else { onEvent(.final(text)) }
      } else { onEvent(.partial(text)) }
    }
    if let message {
      if let completion {
        self.completion = nil; timeout?.cancel()
        completion.resume(throwing: SpeechInputError(message))
      } else { onEvent(.failed(message)) }
    }
  }

  func stop() async throws -> String {
    stopAudio()
    return try await withCheckedThrowingContinuation { continuation in
      completion = continuation
      request?.endAudio()
      timeout = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(10)) } catch { return }
        guard let self, let completion = self.completion else { return }
        self.completion = nil
        completion.resume(throwing: SpeechInputError("Apple speech recognition did not finish. Please try again."))
      }
    }
  }

  func cancel() {
    stopped = true
    timeout?.cancel(); timeout = nil
    stopAudio()
    recognition?.cancel(); recognition = nil
    request = nil
    completion?.resume(throwing: CancellationError()); completion = nil
  }

  private func stopAudio() {
    audio.stop()
    if tapped { audio.inputNode.removeTap(onBus: 0); tapped = false }
    VoiceAudioSession.deactivate()
  }
}

enum VoiceAudioLevel {
  static func measure(_ buffer: AVAudioPCMBuffer) -> Float {
    guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
    var sum: Float = 0
    for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
    return min(sqrt(sum / Float(buffer.frameLength)) * 5, 1)
  }
}

/// The tap alone appends buffers; the main actor only ends or cancels the
/// request, as supported by Speech. Audio buffers never cross an actor boundary.
private final class LegacySpeechAudioSink: @unchecked Sendable {
  private let request: SFSpeechAudioBufferRecognitionRequest
  init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
  func append(_ buffer: AVAudioPCMBuffer) { request.append(buffer) }
}
