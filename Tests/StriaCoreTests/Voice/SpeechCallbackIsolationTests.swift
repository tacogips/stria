@preconcurrency import AVFoundation
@preconcurrency import Speech
import Foundation
@testable import StriaCore
import Testing

@Suite @MainActor struct SpeechCallbackIsolationTests {
  @Test func legacyTapRunsOnBackgroundThreadAndDeliversLevel() async throws {
    let probe = SpeechCallbackProbe()
    let buffer = try makeBuffer()
    let request = SFSpeechAudioBufferRecognitionRequest()
    let tap = LegacyAppleSpeechEngine.makeTap(request: request) { probe.receive($0) }
    await runOnBackgroundThread(makeTapInvocation(tap, buffer: buffer))
    try await waitForVoice { probe.level != nil }
    #expect(abs(try #require(probe.level) - 0.5) < 0.0001)
    request.endAudio()
  }

  @Test func legacyRecognitionHandlerRunsOnBackgroundThreadAndDeliversError() async throws {
    let probe = SpeechCallbackProbe()
    let handler = LegacyAppleSpeechEngine.makeRecognitionHandler { text, final, message in
      MainActor.preconditionIsolated()
      #expect(text == nil)
      #expect(!final)
      probe.message = message
    }
    await runOnBackgroundThread(makeRecognitionInvocation(handler))
    try await waitForVoice { probe.message != nil }
    #expect(probe.message == "background recognition failure")
  }

  @Test func analyzerTapAndConverterRunOnBackgroundThreadAndDeliverAudio() async throws {
    guard #available(macOS 26, iOS 26, *) else { return }
    let probe = SpeechCallbackProbe()
    let buffer = try makeBuffer()
    let outputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
    let converter = try AnalyzerAudioConverter(from: buffer.format, to: outputFormat)
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    let tap = AnalyzerSpeechEngine.makeTap(converter: converter, continuation: continuation) { probe.receive($0) }
    await runOnBackgroundThread(makeTapInvocation(tap, buffer: buffer))
    continuation.finish()
    var count = 0
    for await input in stream {
      #expect(input.buffer.format.sampleRate == 8000)
      #expect(input.buffer.frameLength > 0)
      count += 1
    }
    try await waitForVoice { probe.level != nil }
    #expect(count == 1)
    #expect(abs(try #require(probe.level) - 0.5) < 0.0001)
    #expect(probe.message == nil)
  }

  @Test func authorizationHandlerRunsOnBackgroundThread() async {
    let status = await withCheckedContinuation { continuation in
      let handler = AppleSpeechEngine.makeAuthorizationHandler(continuation)
      let work = BackgroundSpeechCallback(run: makeAuthorizationInvocation(handler))
      Thread { work.run() }.start()
    }
    #expect(status == .denied)
  }

  private func makeBuffer() throws -> AVAudioPCMBuffer {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
    buffer.frameLength = 1024
    let samples = try #require(buffer.floatChannelData?[0])
    for index in 0..<Int(buffer.frameLength) { samples[index] = 0.1 }
    return buffer
  }
}

@MainActor
private final class SpeechCallbackProbe {
  var level: Float?
  var message: String?
  func receive(_ event: SpeechInputEvent) {
    MainActor.preconditionIsolated()
    switch event {
    case .level(let level): self.level = level
    case .failed(let message): self.message = message
    default: Issue.record("Unexpected speech callback event")
    }
  }
}

// Tests transfer framework blocks and synthetic buffers to exactly one worker.
// A real Thread ensures execution cannot occur inline on the main actor (as a
// DispatchQueue.sync call sometimes can). Only the factory blocks are invoked
// there; the test operation itself is created in this nonisolated function.
private struct BackgroundSpeechCallback: @unchecked Sendable {
  let run: () -> Void
}

nonisolated private func runOnBackgroundThread(_ operation: @escaping () -> Void) async {
  let work = BackgroundSpeechCallback(run: operation)
  await withCheckedContinuation { continuation in
    Thread {
      #expect(!Thread.isMainThread)
      work.run()
      continuation.resume()
    }.start()
  }
}

nonisolated private func makeTapInvocation(_ tap: @escaping AVAudioNodeTapBlock, buffer: AVAudioPCMBuffer) -> () -> Void {
  { tap(buffer, AVAudioTime(sampleTime: 0, atRate: 16000)) }
}

nonisolated private func makeRecognitionInvocation(
  _ handler: @escaping (SFSpeechRecognitionResult?, (any Error)?) -> Void
) -> () -> Void {
  { handler(nil, SpeechInputError("background recognition failure")) }
}

nonisolated private func makeAuthorizationInvocation(_ handler: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) -> () -> Void {
  { handler(.denied) }
}
