// Wraps the shared Stria paper icon in a transparent macOS icon canvas.
// Usage: swiftc -O scripts/make-app-icon.swift -o /tmp/make-icon && /tmp/make-icon <output.icns>
import AppKit
import Foundation

let artwork = URL(fileURLWithPath: "Mobile/StriaMobile/Assets.xcassets/AppIcon.appiconset/Stria-Paper.png")
guard let source = NSImage(contentsOf: artwork),
      let sourceImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
  fatalError("Could not load Stria icon artwork")
}

func renderPNG(size: Int) -> Data {
  let scale = CGFloat(size) / 1024
  let image = NSImage(size: NSSize(width: size, height: size))
  image.lockFocus()
  guard let context = NSGraphicsContext.current?.cgContext else { fatalError("no context") }
  context.scaleBy(x: scale, y: scale)

  // macOS icon grid: 824 pt rounded tile centred on a transparent canvas.
  let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
  context.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
  context.clip()
  context.draw(sourceImage, in: tile)
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
