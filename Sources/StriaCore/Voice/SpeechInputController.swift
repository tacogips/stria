import Foundation
import Observation

/// Owns a single dictation session. Every callback is session-scoped, so a
/// cancelled permission request or upload cannot mutate a later session.
@MainActor
@Observable
public final class SpeechInputController {
  public private(set) var state: DictationState = .idle
  public private(set) var elapsedSeconds = 0
  public private(set) var engineName = "apple"
  private let config: () -> StriaConfig.VoiceConfig
  private let makeEngine: (StriaConfig.VoiceConfig) throws -> any SpeechTranscriptionEngine
  private let readInput: () -> String
  private let writeInput: (String) -> Void
  private let notice: (String) -> Void
  private let submit: () -> Void
  private let focus: () -> Void
  private let sleep: @Sendable (Duration) async throws -> Void
  private var engine: (any SpeechTranscriptionEngine)?
  private var operation: Task<Void, Never>?
  private var timer: Task<Void, Never>?
  private var session: UUID?
  private var settings = StriaConfig.VoiceConfig()
  private var dictatedRange = NSRange(location: 0, length: 0)
  private var previousInput = ""
  private var separator = ""

  public init(config: @escaping () -> StriaConfig.VoiceConfig,
              makeEngine: @escaping (StriaConfig.VoiceConfig) throws -> any SpeechTranscriptionEngine,
              readInput: @escaping () -> String, writeInput: @escaping (String) -> Void,
              notice: @escaping (String) -> Void, submit: @escaping () -> Void, focus: @escaping () -> Void = {},
              sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
    self.config = config; self.makeEngine = makeEngine; self.readInput = readInput; self.writeInput = writeInput
    self.notice = notice; self.submit = submit; self.focus = focus; self.sleep = sleep
  }

  public func toggle() {
    if state.isRecording { stop(); return }
    guard !state.isActive else { return }
    settings = config()
    engineName = settings.engine
    elapsedSeconds = 0
    previousInput = readInput()
    dictatedRange = NSRange(location: previousInput.utf16.count, length: 0)
    separator = previousInput.isEmpty || previousInput.last?.isWhitespace == true ? "" : " "
    let id = UUID()
    session = id
    state = .requestingPermission
    operation = Task { [weak self] in
      guard let self else { return }
      do {
        let engine = try makeEngine(settings)
        self.engine = engine
        try await engine.requestPermission()
        guard session == id else { return }
        try Task.checkCancellation()
        state = .preparing
        try await engine.start(language: settings.language) { [weak self] event in self?.receive(event, session: id) }
        guard session == id else { return }
        try Task.checkCancellation()
        state = .recording(level: 0)
        startTimer(session: id)
      } catch {
        if session == id { fail(error.localizedDescription) }
      }
    }
  }

  public func stop() {
    guard state.isRecording, let engine, let id = session else { return }
    timer?.cancel()
    state = .transcribing
    operation = Task { [weak self] in
      do {
        let text = try await engine.stop()
        guard let self, self.session == id else { return }
        self.finish(text)
      } catch {
        guard let self, self.session == id else { return }
        self.fail(error.localizedDescription)
      }
    }
  }

  public func cancel() {
    guard session != nil else { return }
    session = nil
    operation?.cancel(); timer?.cancel()
    engine?.cancel(); engine = nil
    replaceDictation(with: "")
    state = .idle
    focus()
  }

  private func receive(_ event: SpeechInputEvent, session id: UUID) {
    guard session == id else { return }
    switch event {
    case .partial(let text): replaceDictation(with: text.isEmpty ? "" : separator + text)
    case .final(let text): finish(text)
    case .level(let level): if state.isRecording { state = .recording(level: min(max(level, 0), 1)) }
    case .failed(let message): fail(message)
    }
  }

  private func finish(_ text: String) {
    session = nil
    timer?.cancel()
    engine?.cancel(); engine = nil
    replaceDictation(with: text.isEmpty ? "" : separator + text)
    state = .idle
    focus()
    if settings.autoSend, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { submit() }
  }

  private func fail(_ message: String) {
    session = nil
    timer?.cancel()
    engine?.cancel(); engine = nil
    state = .failed(message: message)
    notice(message)
    focus()
  }

  private func startTimer(session id: UUID) {
    let sleep = self.sleep
    timer = Task { [weak self] in
      while !Task.isCancelled {
        do { try await sleep(.seconds(1)) } catch { return }
        guard !Task.isCancelled, let self, self.session == id, self.state.isRecording else { return }
        self.elapsedSeconds += 1
        if self.elapsedSeconds >= self.settings.maxSeconds { self.stop(); return }
      }
    }
  }

  /// Account for user edits before/after the dictated range. If an edit
  /// overlaps dictation, preserve that edit and begin a new range at the end.
  private func replaceDictation(with text: String) {
    let current = readInput()
    if current != previousInput {
      let old = Array(previousInput.utf16), new = Array(current.utf16)
      var prefix = 0
      while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
      var suffix = 0
      while suffix < min(old.count, new.count) - prefix,
            old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
      let oldEnd = old.count - suffix
      if oldEnd <= dictatedRange.location {
        dictatedRange.location += new.count - old.count
      } else if prefix < NSMaxRange(dictatedRange) {
        dictatedRange = NSRange(location: new.count, length: 0)
      }
    }
    let updated = (current as NSString).replacingCharacters(in: dictatedRange, with: text)
    dictatedRange.length = text.utf16.count
    previousInput = updated
    writeInput(updated)
  }
}
