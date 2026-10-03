// Renders Resources/Stria.icns: a white page with text lines, one of them
// highlighted (an OCR search hit), on a solid blue tile.
// Usage: swiftc -O scripts/make-app-icon.swift -o /tmp/make-icon && /tmp/make-icon <output.icns>
import AppKit
import Foundation

func renderPNG(size: Int) -> Data {
  let scale = CGFloat(size) / 1024
  let image = NSImage(size: NSSize(width: size, height: size))
  image.lockFocus()
  guard let context = NSGraphicsContext.current?.cgContext else { fatalError("no context") }
  context.scaleBy(x: scale, y: scale)

  // macOS icon grid: 824 pt tile centred on the 1024 canvas.
  let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
  context.setFillColor(NSColor(srgbRed: 0.10, green: 0.42, blue: 0.95, alpha: 1).cgColor)
  context.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
  context.fillPath()

  // The page.
  let page = CGRect(x: 292, y: 210, width: 440, height: 600)
  context.setFillColor(NSColor.white.cgColor)
  context.addPath(CGPath(roundedRect: page, cornerWidth: 28, cornerHeight: 28, transform: nil))
  context.fillPath()

  // Text lines; the fourth is highlighted.
  let lineHeight: CGFloat = 26
  let widths: [CGFloat] = [340, 300, 340, 250, 330, 280, 320]
  for (index, width) in widths.enumerated() {
    let y = page.maxY - 110 - CGFloat(index) * 66
    if index == 3 {
      context.setFillColor(NSColor(srgbRed: 1.0, green: 0.78, blue: 0.10, alpha: 1).cgColor)
      context.fill(CGRect(x: page.minX + 44, y: y - 14, width: width + 24, height: lineHeight + 28))
      context.setFillColor(NSColor(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 1).cgColor)
    } else {
      context.setFillColor(NSColor(srgbRed: 0.72, green: 0.75, blue: 0.80, alpha: 1).cgColor)
    }
    context.addPath(CGPath(roundedRect: CGRect(x: page.minX + 56, y: y, width: width, height: lineHeight),
                           cornerWidth: 13, cornerHeight: 13, transform: nil))
    context.fillPath()
  }
  image.unlockFocus()
  guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
  return png
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/Stria.icns")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Stria-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
  try renderPNG(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
  try renderPNG(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
print("wrote \(output.path)")
