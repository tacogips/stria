import StriaCore
import Testing

@Test func errorCodesMapToStableExitCodes() {
  let cases: [(ErrorCode, Int32)] = [(.ioError, 1), (.databaseError, 1), (.databaseTooNew, 1), (.idCollision, 1), (.configInvalid, 1),
    (.usageError, 2), (.invalidPDF, 2), (.documentNotFound, 3), (.pageNotFound, 3), (.noRelevantPages, 3), (.serviceUnavailable, 4), (.serviceFailed, 5)]
  for (code, exitCode) in cases { #expect(StriaError(code: code, message: "test").exitCode == exitCode) }
}
