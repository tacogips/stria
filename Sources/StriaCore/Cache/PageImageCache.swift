import Foundation

public struct PageImageCache: Sendable {
  private let paths: StriaPaths

  public init(paths: StriaPaths) {
    self.paths = paths
  }

  public func validCachedURL(docId: String, page: Int, width: Int, height: Int) -> URL? {
    let url = paths.cachedPage(docId: docId, page: page)
    guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
          let fileSize = values.fileSize, fileSize > 0,
          let pixelSize = ImageCodec.pixelSize(ofImageAt: url), pixelSize.width == width, pixelSize.height == height else {
      return nil
    }
    return url
  }

  public func expand(docId: String, page: Int, image: StoredPageImage) throws -> URL {
    let directory = paths.cacheDirectory(docId: docId)
    try createPrivateDirectory(directory)
    let url = paths.cachedPage(docId: docId, page: page)
    try write(image: image, to: url)
    return url
  }

  public func write(image: StoredPageImage, to url: URL) throws {
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let png = try ImageCodec.pngData(ImageCodec.decode(image.data))
      try png.write(to: url, options: .atomic)
    } catch let error as StriaError {
      throw error
    } catch {
      throw StriaError.io("Could not write expanded page image at \(url.path): \(error.localizedDescription)")
    }
  }

  private func createPrivateDirectory(_ url: URL) throws {
    do {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    } catch {
      throw StriaError.io("Could not create page cache directory: \(error.localizedDescription)")
    }
  }
}
