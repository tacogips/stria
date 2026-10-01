import Foundation
import Darwin

public struct RunLogWriter: Sendable {
  private let paths: StriaPaths

  public init(paths: StriaPaths) {
    self.paths = paths
  }

  public func append(_ run: AgentRunRecord) throws {
    let directory = paths.logs
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    } catch {
      throw StriaError.io("Could not prepare run log directory: \(error.localizedDescription)")
    }

    let record: [String: Any] = [
      "runId": run.id,
      "kind": run.kind.rawValue,
      "docId": run.documentId as Any? ?? NSNull(),
      "page": run.pageNumber as Any? ?? NSNull(),
      "vendor": run.vendor,
      "model": run.model as Any? ?? NSNull(),
      "status": run.status.rawValue,
      "imageCount": run.imageCount,
      "startedAt": Self.timestamp(run.startedAt),
      "finishedAt": Self.timestamp(run.finishedAt),
      "durationMs": run.durationMs,
      "error": run.error as Any? ?? NSNull()
    ]
    let data: Data
    do {
      data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) + Data([0x0A])
    } catch {
      throw StriaError.io("Could not encode run log: \(error.localizedDescription)")
    }

    let fd = open(paths.runLog(for: run.startedAt).path, O_WRONLY | O_APPEND | O_CREAT, mode_t(0o600))
    guard fd >= 0 else { throw StriaError.io("Could not open run log: \(String(cString: strerror(errno)))") }
    defer { _ = close(fd) }
    let written = data.withUnsafeBytes { buffer in
      write(fd, buffer.baseAddress, buffer.count)
    }
    guard written == data.count else {
      throw StriaError.io("Could not append run log: \(String(cString: strerror(errno)))")
    }
  }

  private static func timestamp(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }
}
