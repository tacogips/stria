@preconcurrency import AVFoundation
@preconcurrency import Speech
import Foundation

@available(macOS 26, iOS 26, *)
@MainActor
final class AnalyzerSpeechEngine: SpeechTranscriptionEngine {
  private let audio = AVAudioEngine()
  private var analyzer: SpeechAnalyzer?
  private var continuation: AsyncStream<AnalyzerInput>.Continuation?
  private var analysis: Task<Void, any Error>?
  private var results: Task<Void, any Error>?
  private var tapped = false
  private var committed = ""
  private var volatile = ""
  private var reservedLocale: Locale?

  func requestPermission() async throws {}

  func start(language: String, onEvent: @escaping @MainActor @Sendable (SpeechInputEvent) -> Void) async throws {
    let requested = Locale(identifier: language == "auto" ? Locale.preferredLanguages.first ?? Locale.current.identifier : language)
    guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
      throw SpeechInputError("On-device speech recognition does not support this language.")
    }
    try Task.checkCancellation()
    if try await AssetInventory.reserve(locale: locale) { reservedLocale = locale }
    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
      try await installation.downloadAndInstall()
    }
    try Task.checkCancellation()
    try VoiceAudioSession.activate()
    let naturalFormat = audio.inputNode.outputFormat(forBus: 0)
    guard naturalFormat.sampleRate > 0, naturalFormat.channelCount > 0,
          let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: naturalFormat) else {
      throw SpeechInputError("No compatible microphone is available.")
    }
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    self.analyzer = analyzer
    try await analyzer.prepareToAnalyze(in: format)
    try Task.checkCancellation()
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    self.continuation = continuation
    let converter = try AnalyzerAudioConverter(from: naturalFormat, to: format)
    results = Task { [weak self] in
      do {
        for try await result in transcriber.results {
          guard let self, !Task.isCancelled else { return }
          let text = String(result.text.characters)
          if result.isFinal { self.committed += text; self.volatile = "" } else { self.volatile = text }
          onEvent(.partial(self.committed + self.volatile))
        }
      } catch {
        if !Task.isCancelled { onEvent(.failed(error.localizedDescription)) }
        throw error
      }
    }
    analysis = Task {
      do { try await analyzer.start(inputSequence: stream) } catch {
        if !Task.isCancelled { onEvent(.failed(error.localizedDescription)) }
        throw error
      }
    }
    audio.inputNode.installTap(onBus: 0, bufferSize: 1024, format: naturalFormat,
      block: Self.makeTap(converter: converter, continuation: continuation, onEvent: onEvent))
    tapped = true
    audio.prepare()
    try audio.start()
  }

  nonisolated static func makeTap(
    converter: AnalyzerAudioConverter,
    continuation: AsyncStream<AnalyzerInput>.Continuation,
    onEvent: @escaping @MainActor @Sendable (SpeechInputEvent) -> Void
  ) -> AVAudioNodeTapBlock {
    { buffer, _ in
      let level = VoiceAudioLevel.measure(buffer)
      do { continuation.yield(AnalyzerInput(buffer: try converter.convert(buffer))) } catch {
        let message = error.localizedDescription
        Task { @MainActor in onEvent(.failed(message)) }
      }
      Task { @MainActor in onEvent(.level(level)) }
    }
  }

  func stop() async throws -> String {
    stopAudio()
    continuation?.finish()
    try await analysis?.value
    try await analyzer?.finalizeAndFinishThroughEndOfInput()
    try await results?.value
    return committed + volatile
  }

  func cancel() {
    stopAudio()
    continuation?.finish(); continuation = nil
    analysis?.cancel(); results?.cancel()
    analysis = nil; results = nil
    let analyzer = self.analyzer
    self.analyzer = nil
    let locale = reservedLocale
    reservedLocale = nil
    Task {
      await analyzer?.cancelAndFinishNow()
      if let locale { await AssetInventory.release(reservedLocale: locale) }
    }
  }

  private func stopAudio() {
    audio.stop()
    if tapped { audio.inputNode.removeTap(onBus: 0); tapped = false }
    VoiceAudioSession.deactivate()
  }
}

/// AVAudioEngine invokes a tap serially. The converter belongs solely to
/// that tap; every output buffer is newly allocated and transferred to Speech.
final class AnalyzerAudioConverter: @unchecked Sendable {
  private let converter: AVAudioConverter
  private let format: AVAudioFormat

  init(from input: AVAudioFormat, to output: AVAudioFormat) throws {
    guard let converter = AVAudioConverter(from: input, to: output) else {
      throw SpeechInputError("Could not prepare microphone audio conversion.")
    }
    self.converter = converter; self.format = output
  }

  nonisolated func convert(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
    let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * format.sampleRate / input.format.sampleRate)) + 32
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
      throw SpeechInputError("Could not allocate microphone audio.")
    }
    let inputSource = AnalyzerInputSource(input)
    var error: NSError?
    let status = converter.convert(to: output, error: &error, withInputFrom: Self.makeInputBlock(inputSource))
    if let error { throw error }
    guard status != .error else { throw SpeechInputError("Microphone audio conversion failed.") }
    return output
  }

  nonisolated private static func makeInputBlock(_ inputSource: AnalyzerInputSource) -> AVAudioConverterInputBlock {
    { _, state in
      guard let input = inputSource.take() else { state.pointee = .noDataNow; return nil }
      state.pointee = .haveData
      return input
    }
  }
}

/// The converter's input callback may be marked Sendable by the SDK.
private final class AnalyzerInputSource: @unchecked Sendable {
  private let lock = NSLock()
  private var buffer: AVAudioPCMBuffer?
  init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
  func take() -> AVAudioPCMBuffer? {
    lock.lock(); defer { lock.unlock() }
    let result = buffer
    buffer = nil
    return result
  }
}
