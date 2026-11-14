@preconcurrency import AVFoundation
import Foundation

@MainActor
public protocol VoiceAudioRecording: AnyObject {
  func start(in cache: URL, onLevel: @escaping @MainActor @Sendable (Float) -> Void) throws -> URL
  func stop() throws
  func cancel()
}

@MainActor
public final class AudioRecorder: VoiceAudioRecording {
  private var recorder: AVAudioRecorder?
  private var file: URL?
  private var meter: Task<Void, Never>?
  public init() {}

  public func start(in cache: URL, onLevel: @escaping @MainActor @Sendable (Float) -> Void) throws -> URL {
    try VoiceAudioSession.activate()
    do {
      try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
      let url = cache.appendingPathComponent("dictation-\(UUID().uuidString).m4a")
      file = url
      let recorder = try AVAudioRecorder(url: url, settings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue, AVEncoderBitRateKey: 64000
      ])
      self.recorder = recorder
      recorder.isMeteringEnabled = true
      guard recorder.record() else { throw SpeechInputError("Could not start the microphone.") }
      meter = Task { [weak self] in
        while !Task.isCancelled {
          do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
          guard let recorder = self?.recorder else { return }
          recorder.updateMeters()
          onLevel(pow(10, recorder.averagePower(forChannel: 0) / 20))
        }
      }
      return url
    } catch { cancel(); throw error }
  }

  public func stop() throws {
    meter?.cancel(); meter = nil
    recorder?.stop(); recorder = nil
    VoiceAudioSession.deactivate()
    guard let file, (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0 > 0 else {
      throw SpeechInputError("No microphone audio was recorded.")
    }
  }

  public func cancel() {
    meter?.cancel(); meter = nil
    recorder?.stop(); recorder = nil
    if let file { try? FileManager.default.removeItem(at: file) }
    file = nil
    VoiceAudioSession.deactivate()
  }
}

enum VoiceAudioSession {
  static func activate() throws {
    #if os(iOS)
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement, options: [])
    try session.setActive(true)
    #endif
  }

  static func deactivate() {
    #if os(iOS)
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    #endif
  }
}

@MainActor
enum VoicePermissions {
  static func microphone() async throws {
    #if os(iOS)
    let granted = await AVAudioApplication.requestRecordPermission()
    #else
    let granted = await AVCaptureDevice.requestAccess(for: .audio)
    #endif
    guard granted else {
      throw SpeechInputError("Microphone access was denied. Enable Stria in Settings > Privacy & Security > Microphone (System Settings on Mac).")
    }
  }
}
