import CoreGraphics
import Foundation
import StriaCore

func askStoredImage() throws -> StoredPageImage {
  guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                               space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
        let image = context.makeImage() else { throw StriaError.io("Could not create ask test image") }
  return try ImageCodec.encode(image, preferred: .jpeg, quality: 0.8)
}

func prepareAskDocument(paths: StriaPaths, id: String, pageCount: Int = 3, texts: [Int: String] = [:]) async throws -> StriaStore {
  let store = try openStorage(paths: paths)
  let base = storageDocument(id)
  let document = DocumentRecord(id: base.id, sha256: base.sha256, title: base.title, originalFilename: base.originalFilename,
                                originalPath: base.originalPath, byteSize: base.byteSize, pageCount: pageCount,
                                importStatus: .ready, renderDPI: base.renderDPI, imageFormat: .jpeg,
                                importedAt: base.importedAt, updatedAt: base.updatedAt)
  try await store.insertDocument(document)
  let image = try askStoredImage()
  for page in 1...pageCount {
    try await store.insertPage(documentId: id, pageNumber: page, image: image)
    if let text = texts[page] {
      try await store.recordOCRSuccess(documentId: id, page: page, text: text, vendor: "fake", model: nil,
                                       run: storageRun("ocr-\(id)-\(page)", documentId: id, page: page))
    }
  }
  return store
}
