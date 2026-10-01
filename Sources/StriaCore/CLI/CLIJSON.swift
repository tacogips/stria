import Foundation

public struct CommandOutput: Equatable, Sendable {
  public var stdout: String
  public var stderr: String
  public var exitCode: Int32

  public init(stdout: String, stderr: String, exitCode: Int32) {
    self.stdout = stdout
    self.stderr = stderr
    self.exitCode = exitCode
  }
}

public enum JSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case let .bool(value): try container.encode(value)
    case let .int(value): try container.encode(value)
    case let .double(value): try container.encode(value)
    case let .string(value): try container.encode(value)
    case let .array(value): try container.encode(value)
    case let .object(value): try container.encode(value)
    }
  }
}

public enum CLIJSON {
  private struct ErrorEnvelope: Encodable {
    let error: ErrorBody
  }

  private struct ErrorBody: Encodable {
    let code: ErrorCode
    let message: String
  }

  public static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(StriaDateFormat.string(from: date))
    }
    return encoder
  }

  public static func success<T: Encodable>(_ value: T) throws -> CommandOutput {
    let data = try makeEncoder().encode(value)
    guard let json = String(data: data, encoding: .utf8) else {
      throw StriaError.io("Could not encode command output as UTF-8")
    }
    return CommandOutput(stdout: json + "\n", stderr: "", exitCode: 0)
  }

  public static func failure(_ error: StriaError) -> CommandOutput {
    let envelope = ErrorEnvelope(error: ErrorBody(code: error.code, message: error.message))
    let data = try? makeEncoder().encode(envelope)
    let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{\"error\":{\"code\":\"\(error.code.rawValue)\",\"message\":\"\(error.message)\"}}"
    return CommandOutput(stdout: "", stderr: json + "\n", exitCode: error.exitCode)
  }
}
