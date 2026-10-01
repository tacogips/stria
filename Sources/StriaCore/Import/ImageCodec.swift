import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageCodec {
  public static func encode(_ image: CGImage, preferred: ImageFormat, quality: Double) throws -> StoredPageImage {
    let clampedQuality = min(1, max(0, quality))
    if preferred == .heic, let data = encoded(image, type: .heic, quality: clampedQuality) {
      return StoredPageImage(data: data, format: .heic, width: image.width, height: image.height)
    }
    guard let data = encoded(image, type: .jpeg, quality: clampedQuality) else {
      throw StriaError.io("ImageIO could not encode the page as JPEG")
    }
    return StoredPageImage(data: data, format: .jpeg, width: image.width, height: image.height)
  }

  public static func decode(_ data: Data) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      throw StriaError.io("ImageIO could not decode the stored page image")
    }
    return image
  }

  public static func pngData(_ image: CGImage) throws -> Data {
    guard let data = encoded(image, type: .png, quality: nil) else {
      throw StriaError.io("ImageIO could not encode the page as PNG")
    }
    return data
  }

  public static func pixelSize(ofImageAt url: URL) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
          let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
      return nil
    }
    return (width.intValue, height.intValue)
  }

  private static func encoded(_ image: CGImage, type: UTType, quality: Double?) -> Data? {
    let destinationData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(destinationData, type.identifier as CFString, 1, nil) else {
      return nil
    }
    let properties: [CFString: Any]? = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return destinationData as Data
  }
}
