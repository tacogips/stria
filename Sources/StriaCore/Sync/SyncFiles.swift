import Darwin
import Foundation

/// All shared-folder access is coordinated. Writes publish a complete sibling
/// temporary file with POSIX rename, including replacement of existing files.
struct SyncFiles: Sendable {
  let coordinator: any SyncFileCoordinating

  init(coordinator: any SyncFileCoordinating = SystemSyncFileCoordinator()) { self.coordinator = coordinator }

  func coordinate<T>(_ url: URL, writing: Bool = false, _ body: (URL) throws -> T) throws -> T {
    var result: Result<T, Error>?
    try coordinator.coordinate(url, writing: writing) { coordinated in result = Result { try body(coordinated) } }
    guard let result else { throw StriaError.io("Could not coordinate sync file") }
    return try result.get()
  }

  func exists(_ url: URL) throws -> Bool {
    // Coordinate an existing ancestor when probing an absent child: read
    // coordination of a missing file may fail before the accessor runs.
    var ancestor = url.deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
      ancestor.deleteLastPathComponent()
    }
    return try coordinate(ancestor) { _ in FileManager.default.fileExists(atPath: url.path) }
  }

  func children(_ url: URL) throws -> [URL] {
    guard try exists(url) else { return [] }
    return try coordinate(url) { url in
      guard FileManager.default.fileExists(atPath: url.path) else { return [] }
      return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
  }

  func createDirectory(_ url: URL) throws {
    try coordinate(url, writing: true) { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) }
  }

  func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
    try coordinate(url) { url in try Self.decoder().decode(type, from: Data(contentsOf: url)) }
  }

  func write<T: Encodable>(_ value: T, at url: URL) throws { try writeData(Self.encoder().encode(value), at: url) }

  func writeData(_ data: Data, at url: URL) throws {
    try createDirectory(url.deletingLastPathComponent())
    try coordinate(url, writing: true) { destination in
      let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
      defer { try? FileManager.default.removeItem(at: temporary) }
      try data.write(to: temporary)
      guard rename(temporary.path, destination.path) == 0 else { throw StriaError.io("Could not publish sync file: \(destination.lastPathComponent)") }
    }
  }

  func copy(_ source: URL, to destination: URL) throws {
    // Read a coordinated snapshot; the import pipeline can then run without
    // holding an iCloud read lock across asynchronous rendering.
    let data = try coordinate(source) { try Data(contentsOf: $0) }
    try writeData(data, at: destination)
  }

  func remove(_ url: URL) throws {
    try coordinate(url, writing: true) { if FileManager.default.fileExists(atPath: $0.path) { try FileManager.default.removeItem(at: $0) } }
  }

  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var c = encoder.singleValueContainer(); try c.encode(StriaDateFormat.string(from: date))
    }
    return encoder
  }

  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let c = try decoder.singleValueContainer()
      let value = try c.decode(String.self)
      guard let date = StriaDateFormat.date(from: value) else {
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid sync date")
      }
      return date
    }
    return decoder
  }
}
