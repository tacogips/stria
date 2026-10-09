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

  /// Downsample directly from encoded bytes without first allocating a full-size bitmap.
  public static func thumbnail(data: Data, maxPixel: Int) throws -> CGImage {
    guard maxPixel > 0 else { throw StriaError.io("Thumbnail size must be positive") }
    return try autoreleasepool {
      let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true
      ]
      guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        throw StriaError.io("ImageIO could not decode the page thumbnail")
      }
      return image
    }
  }

  /// A downscaled copy whose longest side is at most `maxPixel` (the image
  /// itself when it is already small enough).
  public static func thumbnail(of image: CGImage, maxPixel: Int) -> CGImage {
    let longest = max(image.width, image.height)
    guard longest > maxPixel, maxPixel > 0 else { return image }
    let scale = CGFloat(maxPixel) / CGFloat(longest)
    let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
    let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage() ?? image
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
