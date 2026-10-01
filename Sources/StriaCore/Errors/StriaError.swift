public enum ErrorCode: String, Codable, Sendable {
  case ioError, databaseError, databaseTooNew, idCollision, configInvalid
  case usageError, invalidPDF, documentNotFound, pageNotFound, noRelevantPages
  case serviceUnavailable, serviceFailed
}

public struct StriaError: Error, Equatable, Sendable {
  public let code: ErrorCode
  public let message: String

  public var exitCode: Int32 {
    switch code {
    case .ioError, .databaseError, .databaseTooNew, .idCollision, .configInvalid: 1
    case .usageError, .invalidPDF: 2
    case .documentNotFound, .pageNotFound, .noRelevantPages: 3
    case .serviceUnavailable: 4
    case .serviceFailed: 5
    }
  }

  public init(code: ErrorCode, message: String) {
    self.code = code
    self.message = message
  }

  public static func io(_ message: String) -> Self { .init(code: .ioError, message: message) }
  public static func database(_ message: String) -> Self { .init(code: .databaseError, message: message) }
  public static func databaseTooNew(_ message: String) -> Self { .init(code: .databaseTooNew, message: message) }
  public static func idCollision(_ message: String) -> Self { .init(code: .idCollision, message: message) }
  public static func config(_ message: String) -> Self { .init(code: .configInvalid, message: message) }
  public static func usage(_ message: String) -> Self { .init(code: .usageError, message: message) }
  public static func invalidPDF(_ message: String) -> Self { .init(code: .invalidPDF, message: message) }
  public static func documentNotFound(_ message: String) -> Self { .init(code: .documentNotFound, message: message) }
  public static func pageNotFound(_ message: String) -> Self { .init(code: .pageNotFound, message: message) }
  public static func noRelevantPages(_ message: String) -> Self { .init(code: .noRelevantPages, message: message) }
  public static func serviceUnavailable(_ message: String) -> Self { .init(code: .serviceUnavailable, message: message) }
  public static func serviceFailed(_ message: String) -> Self { .init(code: .serviceFailed, message: message) }
}
