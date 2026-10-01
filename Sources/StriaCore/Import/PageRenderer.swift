import CoreGraphics
import Foundation
import PDFKit

public enum PageRenderer {
  public static func render(page: PDFPage, dpi: Int, maxPixelDimension: Int) throws -> CGImage {
    guard dpi > 0, maxPixelDimension > 0 else {
      throw StriaError.io("DPI and maximum pixel dimension must be positive")
    }
    let cropBounds = page.bounds(for: .cropBox)
    guard cropBounds.width.isFinite, cropBounds.height.isFinite, cropBounds.width > 0, cropBounds.height > 0 else {
      throw StriaError.io("PDF page has invalid crop-box dimensions")
    }
    let rotation = ((page.rotation % 360) + 360) % 360
    let swapsDimensions = rotation == 90 || rotation == 270
    let widthInPoints = swapsDimensions ? cropBounds.height : cropBounds.width
    let heightInPoints = swapsDimensions ? cropBounds.width : cropBounds.height
    let requestedScale = CGFloat(dpi) / 72
    let scale = min(requestedScale, CGFloat(maxPixelDimension) / max(widthInPoints, heightInPoints))
    let width = max(1, Int((widthInPoints * scale).rounded()))
    let height = max(1, Int((heightInPoints * scale).rounded()))
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
          ) else {
      throw StriaError.io("Could not create page rendering context")
    }
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: scale, y: scale)
    page.draw(with: .cropBox, to: context)
    guard let image = context.makeImage() else { throw StriaError.io("Could not create rendered page image") }
    return image
  }
}
