import CoreGraphics
import CoreText
import Foundation

func makePDF(at url: URL, variant: String) throws {
  guard variant == "a" || variant == "b" else { throw NSError(domain: "make-sample-pdf", code: 1) }
  guard let consumer = CGDataConsumer(url: url as CFURL) else { throw NSError(domain: "make-sample-pdf", code: 2) }
  var box = CGRect(x: 0, y: 0, width: 612, height: 792)
  guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
    throw NSError(domain: "make-sample-pdf", code: 3)
  }
  let rows = variant == "b"
    ? ["Document B page 1 学習", "zebra quantum lattice 学習", "Document B page 3" ]
    : ["Document A page 1 学習", "Document A page 2", "Document A page 3"]
  for text in rows {
    context.beginPDFPage(nil)
    let font = CTFontCreateWithName("Hiragino Sans" as CFString, 24, nil)
    let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [fontKey: font]))
    context.textPosition = CGPoint(x: 48, y: 700)
    CTLineDraw(line, context)
    context.endPDFPage()
  }
  context.closePDF()
}

guard CommandLine.arguments.count == 3 else {
  fputs("usage: make-sample-pdf.swift <out.pdf> <a|b>\n", stderr)
  exit(2)
}
do {
  try makePDF(at: URL(fileURLWithPath: CommandLine.arguments[1]), variant: CommandLine.arguments[2])
} catch {
  fputs("could not generate sample PDF: \(error.localizedDescription)\n", stderr)
  exit(1)
}
