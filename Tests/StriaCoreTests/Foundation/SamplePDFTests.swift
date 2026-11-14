import Foundation
import PDFKit
import StriaCore
import Testing

@Test func samplePDFHasPagesAndJapaneseTextLayer() async throws {
  try await withTestDataRoot { paths in
    let pdf = paths.root.appendingPathComponent("sample.pdf")
    try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
    try SamplePDFFactory.makePDF(at: pdf, pages: ["First page", "日本語の学習 page two", "Third page"])
    let document = try #require(PDFDocument(url: pdf))
    #expect(document.pageCount == 3)
    #expect(document.page(at: 1)?.string?.contains("日本語") == true)
  }
}
