import CoreGraphics
import Foundation
import PDFKit
import StriaCore
import Testing

@Suite("IdentityTests")
struct IdentityTests {
  @Test func hashesBytesIndependentOfPathAndChangesWithContent() async throws {
    try await withTestDataRoot { paths in
      let first = paths.root.appendingPathComponent("first.pdf")
      let copy = paths.root.appendingPathComponent("copy.pdf")
      let changed = paths.root.appendingPathComponent("changed.pdf")
      try Data("same bytes".utf8).write(to: first)
      try Data("same bytes".utf8).write(to: copy)
      try Data("different".utf8).write(to: changed)

      let firstHash = try DocumentIdentity.sha256Hex(of: first)
      let copyHash = try DocumentIdentity.sha256Hex(of: copy)
      let changedHash = try DocumentIdentity.sha256Hex(of: changed)
      #expect(firstHash == copyHash)
      #expect(DocumentIdentity.docId(sha256Hex: firstHash) == DocumentIdentity.docId(sha256Hex: copyHash))
      #expect(DocumentIdentity.docId(sha256Hex: firstHash) != DocumentIdentity.docId(sha256Hex: changedHash))
      #expect(DocumentIdentity.docId(sha256Hex: firstHash).count == 16)
      #expect(DocumentIdentity.docId(sha256Hex: firstHash).allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }
  }
}

@Suite("InspectorTests")
struct InspectorTests {
  @Test func rejectsNonPDFAndUsesFilenameWhenTitleIsMissing() async throws {
    try await withTestDataRoot { paths in
      let invalid = paths.root.appendingPathComponent("invalid.pdf")
      try SamplePDFFactory.writeNotAPDF(at: invalid)
      #expect(throws: StriaError.self) { try PDFInspector.inspect(url: invalid) }

      let pdf = paths.root.appendingPathComponent("filename-title.pdf")
      try SamplePDFFactory.makePDF(at: pdf, pages: ["one", "two"])
      let inspection = try PDFInspector.inspect(url: pdf)
      #expect(inspection.title == "filename-title")
      #expect(inspection.pageCount == 2)
    }
  }

  @Test func readsTrimmedPDFTitle() async throws {
    try await withTestDataRoot { paths in
      let source = paths.root.appendingPathComponent("source.pdf")
      let titled = paths.root.appendingPathComponent("titled.pdf")
      try SamplePDFFactory.makePDF(at: source, pages: ["report"])
      let document = try #require(PDFDocument(url: source))
      document.documentAttributes = [PDFDocumentAttribute.titleAttribute: "  Report  "]
      #expect(document.write(to: titled))
      #expect(try PDFInspector.inspect(url: titled).title == "Report")
    }
  }
}

@Suite("RenderCodecTests")
struct RenderCodecTests {
  @Test func rendersAtDPIWithCapAndRotation() async throws {
    try await withTestDataRoot { paths in
      let pdf = paths.root.appendingPathComponent("render.pdf")
      try SamplePDFFactory.makePDF(at: pdf, pages: ["render"])
      let document = try #require(PDFDocument(url: pdf))
      let page = try #require(document.page(at: 0))
      let standard = try PageRenderer.render(page: page, dpi: 150, maxPixelDimension: 4096)
      #expect(standard.width == 1275)
      #expect(standard.height == 1650)

      let capped = try PageRenderer.render(page: page, dpi: 600, maxPixelDimension: 4096)
      #expect(max(capped.width, capped.height) <= 4096)
      page.rotation = 90
      let rotated = try PageRenderer.render(page: page, dpi: 150, maxPixelDimension: 4096)
      #expect(rotated.width > rotated.height)
    }
  }

  @Test func imageFormatsRoundTripAndPNGHasSignature() throws {
    let image = try sampleImage(width: 12, height: 8)
    let preferredHEIC = try ImageCodec.encode(image, preferred: .heic, quality: 0.75)
    #expect(preferredHEIC.format == .heic || preferredHEIC.format == .jpeg)
    let decodedHEIC = try ImageCodec.decode(preferredHEIC.data)
    #expect(decodedHEIC.width == image.width)
    #expect(decodedHEIC.height == image.height)

    let jpeg = try ImageCodec.encode(image, preferred: .jpeg, quality: 0.75)
    #expect(jpeg.format == .jpeg)
    let decodedJPEG = try ImageCodec.decode(jpeg.data)
    #expect(decodedJPEG.width == image.width)
    #expect(decodedJPEG.height == image.height)
    #expect(try ImageCodec.pngData(image).prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
  }
}

@Suite("OutlineTests")
struct OutlineTests {
  @Test func extractsPageDestinationsAndRoundTripsJSON() async throws {
    try await withTestDataRoot { paths in
      let source = paths.root.appendingPathComponent("outline-source.pdf")
      let outlined = paths.root.appendingPathComponent("outlined.pdf")
      try SamplePDFFactory.makePDF(at: source, pages: ["one", "two"])
      let document = try #require(PDFDocument(url: source))
      let root = PDFOutline()
      let pageEntry = PDFOutline()
      pageEntry.label = "Second page"
      pageEntry.destination = PDFDestination(page: try #require(document.page(at: 1)), at: .zero)
      let noDestination = PDFOutline()
      noDestination.label = "No page"
      root.insertChild(pageEntry, at: 0)
      root.insertChild(noDestination, at: 1)
      document.outlineRoot = root
      #expect(document.write(to: outlined))

      let reopened = try #require(PDFDocument(url: outlined))
      let nodes = OutlineExtractor.extract(from: reopened)
      #expect(nodes == [OutlineNode(title: "Second page", page: 2), OutlineNode(title: "No page", page: nil)])
      #expect(OutlineExtractor.decodeJSON(OutlineExtractor.encodeJSON(nodes)) == nodes)
      #expect(OutlineExtractor.extract(from: try #require(PDFDocument(url: source))).isEmpty)
      #expect(OutlineExtractor.decodeJSON("not JSON").isEmpty)
    }
  }
}

@Suite("PageImageCacheTests")
struct PageImageCacheTests {
  @Test func expandsValidatesAndRewritesInvalidCacheFiles() async throws {
    try await withTestDataRoot { paths in
      let image = try ImageCodec.encode(sampleImage(width: 12, height: 8), preferred: .jpeg, quality: 0.9)
      let cache = PageImageCache(paths: paths)
      let url = try cache.expand(docId: "doc", page: 1, image: image)
      #expect(url == paths.cachedPage(docId: "doc", page: 1))
      #expect(ImageCodec.pixelSize(ofImageAt: url)?.width == image.width)
      #expect(cache.validCachedURL(docId: "doc", page: 1, width: image.width, height: image.height) == url)

      try Data().write(to: url)
      #expect(cache.validCachedURL(docId: "doc", page: 1, width: image.width, height: image.height) == nil)
      try pngData(width: 1, height: 1).write(to: url)
      #expect(cache.validCachedURL(docId: "doc", page: 1, width: image.width, height: image.height) == nil)
      _ = try cache.expand(docId: "doc", page: 1, image: image)
      #expect(cache.validCachedURL(docId: "doc", page: 1, width: image.width, height: image.height) == url)
    }
  }

  @Test func explicitWriteDoesNotCreateCacheDirectory() async throws {
    try await withTestDataRoot { paths in
      let image = try ImageCodec.encode(sampleImage(width: 3, height: 2), preferred: .jpeg, quality: 0.9)
      let output = paths.root.appendingPathComponent("output/page.png")
      try PageImageCache(paths: paths).write(image: image, to: output)
      #expect(FileManager.default.fileExists(atPath: output.path))
      #expect(!FileManager.default.fileExists(atPath: paths.cache.path))
    }
  }
}

private func sampleImage(width: Int, height: Int) throws -> CGImage {
  guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
        let image = context.makeImage() else {
    throw StriaError.io("Could not create test image")
  }
  return image
}

private func pngData(width: Int, height: Int) throws -> Data {
  try ImageCodec.pngData(sampleImage(width: width, height: height))
}
