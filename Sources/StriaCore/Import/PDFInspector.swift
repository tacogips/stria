import Foundation
import PDFKit

public struct PDFInspection: Equatable, Sendable {
  public let pageCount: Int
  public let title: String

  public init(pageCount: Int, title: String) {
    self.pageCount = pageCount
    self.title = title
  }
}

public enum PDFInspector {
  public static func inspect(url: URL) throws -> PDFInspection {
    guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else {
      throw StriaError.invalidPDF("The file is not a readable, unlocked PDF with pages: \(url.lastPathComponent)")
    }
    let metadataTitle = (document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = metadataTitle.flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent
    return PDFInspection(pageCount: document.pageCount, title: title)
  }
}
