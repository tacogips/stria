import Foundation

public extension StriaLibrary {
  func ocrEvents(documentId: String, selection: OCRSelection) -> AsyncStream<OCREvent> {
    AsyncStream { continuation in
      let task = Task {
        do {
          let summary = try await OCRCoordinator(library: self).run(documentId: documentId, selection: selection) {
            continuation.yield(.progress($0))
          }
          continuation.yield(.finished(summary))
        } catch let error as StriaError {
          continuation.yield(.failed(error))
        } catch is CancellationError {
          continuation.finish()
          return
        } catch {
          continuation.yield(.failed(.io("OCR failed: \(error.localizedDescription)")))
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func runOCR(documentId: String, selection: OCRSelection) async throws -> OCRRunSummary {
    for await event in ocrEvents(documentId: documentId, selection: selection) {
      switch event {
      case .finished(let summary): return summary
      case .failed(let error): throw error
      case .progress: break
      }
    }
    if Task.isCancelled { throw CancellationError() }
    throw StriaError.io("OCR stream ended without a result")
  }
}
