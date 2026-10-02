import Foundation

enum DocumentCommands {
  static func run(_ command: CLICommand, library: StriaLibrary, currentDirectory: URL) async throws -> any Encodable {
    switch command {
    case .importPDF(let path, let noOCR, let forceOCR):
      let source = resolve(path, relativeTo: currentDirectory)
      // Without a flag the config decides (ocr.autoRunOnImport), as in the app.
      let runOCR = !noOCR && (forceOCR || library.environment.config.ocr.autoRunOnImport)
      let result = try await library.importDocument(at: source, runOCR: runOCR)
      return ImportOutput(alreadyImported: result.alreadyImported, document: result.document, ocr: ImportOCROutput(result.ocr))
    case .ocr(let docId, let pages, let retryFailed):
      let selection: OCRSelection
      if let pages {
        let record = try await library.document(id: docId)
        selection = .pages(try PageListParser.parse(pages, pageCount: record.pageCount))
      } else {
        selection = retryFailed ? .pendingAndFailed : .pending
      }
      let result = try await library.runOCR(documentId: docId, selection: selection)
      if let reason = result.unavailableReason { throw StriaError.serviceUnavailable(reason) }
      return OCROutput(result)
    case .list:
      return ListOutput(documents: try await library.listDocuments())
    case .show(let docId):
      let record = try await library.document(id: docId)
      let summary = try await library.summary(of: record)
      let shown = ShowDocumentOutput(
        id: summary.id, title: summary.title, pageCount: summary.pageCount, importStatus: summary.importStatus,
        importedAt: summary.importedAt, originalPath: summary.originalPath, ocr: summary.ocr,
        sha256: record.sha256, byteSize: record.byteSize, renderDpi: record.renderDPI,
        imageFormat: record.imageFormat, ocrVendor: record.ocrVendor, ocrModel: record.ocrModel
      )
      return ShowOutput(document: shown, outline: try await library.outline(documentId: docId))
    case .remove(let docId):
      try await library.removeDocument(id: docId)
      return RemoveOutput(docId: docId, removed: true)
    case .pageImage(let docId, let page, let output):
      let destination = output.map { resolve($0, relativeTo: currentDirectory) }
      let result = try await library.pageImage(documentId: docId, page: page, output: destination)
      return PageImageOutput(docId: result.docId, page: result.page, path: result.path.path,
                             width: result.width, height: result.height, format: "png", cached: result.cached)
    case .pageText(let docId, let page):
      let result = try await library.pageText(documentId: docId, page: page)
      return PageTextOutput(docId: docId, page: page, ocrStatus: result.ocrStatus,
                            text: result.ocrStatus == .done ? result.ocrText : nil,
                            ocrError: result.ocrError, ocrVendor: result.ocrVendor, ocrModel: result.ocrModel)
    default:
      throw StriaError.usage("Not a document command")
    }
  }

  private static func resolve(_ path: String, relativeTo directory: URL) -> URL {
    URL(fileURLWithPath: path, relativeTo: directory).standardizedFileURL
  }
}
