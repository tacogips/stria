import Foundation

/// An app started from Finder or the Dock gets launchd's minimal environment:
/// no PATH entries for Homebrew, mise or npm, and none of the API key
/// variables the user exports in their shell. Before the services are
/// created, Stria reads the login shell's environment once and fills in
/// what is missing, so `claude`, `codex` and the key variables resolve the
/// same way they do in a terminal. Variables already set are kept.
public enum LoginEnvironment {
  /// True when the process was not started from a terminal.
  public static func isGUILaunch(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
    environment["TERM"] == nil && environment["STRIA_SKIP_LOGIN_ENV"] == nil
  }

  /// Runs `$SHELL -l -c 'env -0'` with a timeout and parses the result.
  public static func capture(shell: String? = ProcessInfo.processInfo.environment["SHELL"],
                             timeout: TimeInterval = 5) -> [String: String] {
    let shellPath = shell.flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: shellPath)
    process.arguments = ["-l", "-c", "env -0"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    do { try process.run() } catch { return [:] }
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    if process.isRunning { process.terminate(); return [:] }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    return parse(data)
  }

  static func parse(_ data: Data) -> [String: String] {
    var result: [String: String] = [:]
    for entry in data.split(separator: 0) {
      guard let text = String(data: Data(entry), encoding: .utf8), let equals = text.firstIndex(of: "=") else { continue }
      result[String(text[..<equals])] = String(text[text.index(after: equals)...])
    }
    return result
  }

  /// Variables that describe the shell session rather than the user's setup.
  static let ignored: Set<String> = ["PWD", "OLDPWD", "SHLVL", "_", "TERM", "TERM_PROGRAM", "TERM_SESSION_ID", "TMPDIR", "SHELL"]

  /// Which variables to set: everything missing from `current`, plus PATH
  /// (the login PATH first, then any current entries it lacks).
  public static func additions(current: [String: String], login: [String: String]) -> [String: String] {
    var additions: [String: String] = [:]
    for (key, value) in login where !ignored.contains(key) && current[key] == nil {
      additions[key] = value
    }
    if let loginPath = login["PATH"], !loginPath.isEmpty {
      var parts = loginPath.split(separator: ":").map(String.init)
      for part in (current["PATH"] ?? "").split(separator: ":").map(String.init) where !parts.contains(part) {
        parts.append(part)
      }
      additions["PATH"] = parts.joined(separator: ":")
    }
    return additions
  }

  /// Captures the login environment and applies it to this process.
  public static func importIfNeeded() {
    let current = ProcessInfo.processInfo.environment
    guard isGUILaunch(current) else { return }
    for (key, value) in additions(current: current, login: capture()) {
      setenv(key, value, 1)
    }
  }
}
