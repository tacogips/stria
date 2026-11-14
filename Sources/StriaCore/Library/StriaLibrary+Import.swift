import Foundation

public extension StriaLibrary {
  func importEvents(at url: URL, runOCR: Bool) -> AsyncStream<ImportEvent> {
    AsyncStream { continuation in
      let task = Task { await ImportCoordinator(library: self).run(url: url, runOCR: runOCR, continuation: continuation) }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func importDocument(at url: URL, runOCR: Bool) async throws -> ImportResult {
    var result: ImportResult?
    for await event in importEvents(at: url, runOCR: runOCR) {
      switch event {
      case .finished(let value): result = value
      case .failed(let error): throw error
      case .copied, .rendered, .ocr: break
      }
    }
    guard let result else {
      try Task.checkCancellation()
      throw StriaError.io("Import stream ended without a result")
    }
    return result
  }
}
