import CoreGraphics
import CoreText
import Foundation
import StriaCore

public enum SamplePDFFactory {
  public static func makePDF(at url: URL, pages: [String], pageSize: CGSize = CGSize(width: 612, height: 792)) throws {
    guard let consumer = CGDataConsumer(url: url as CFURL) else { throw StriaError.io("Could not create PDF data consumer") }
    var mediaBox = CGRect(origin: .zero, size: pageSize)
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { throw StriaError.io("Could not create PDF context") }
    for text in pages {
      context.beginPDFPage(nil)
      let attributed = NSAttributedString(string: text, attributes: [.font: CTFontCreateWithName("Hiragino Sans" as CFString, 18, nil)])
      let framesetter = CTFramesetterCreateWithAttributedString(attributed)
      let path = CGPath(rect: CGRect(x: 36, y: 36, width: pageSize.width - 72, height: pageSize.height - 72), transform: nil)
      CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil), context)
      context.endPDFPage()
    }
    context.closePDF()
  }

  public static func writeNotAPDF(at url: URL) throws { try Data("not a PDF".utf8).write(to: url) }
}
