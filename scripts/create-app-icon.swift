import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func writeIcon(size: Int, filename: String) throws {
  let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
  context.setFillColor(CGColor(red: 0.07, green: 0.14, blue: 0.23, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
  context.setFillColor(CGColor(red: 0.95, green: 0.97, blue: 1, alpha: 1))
  for rectangle in [
    CGRect(x: 240, y: 652, width: 544, height: 116),
    CGRect(x: 322, y: 332, width: 380, height: 284),
    CGRect(x: 202, y: 206, width: 620, height: 90),
  ] {
    context.addPath(
      CGPath(roundedRect: rectangle, cornerWidth: 16, cornerHeight: 16, transform: nil))
    context.fillPath()
  }
  let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset/" + filename)
  try FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
  let destination = CGImageDestinationCreateWithURL(
    output as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, context.makeImage()!, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("Could not write app icon") }

}
try writeIcon(size: 1024, filename: "AppIcon.png")
var images: [[String: String]] = [
  ["filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]
]
var written = Set<Int>()
for points in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = points * scale
    let filename = "Mac-\(pixels).png"
    if written.insert(pixels).inserted { try writeIcon(size: pixels, filename: filename) }
    images.append([
      "filename": filename, "idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x",
    ])
  }
}
let metadata = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  .appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset/Contents.json")
try JSONSerialization.data(
  withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]],
  options: [.prettyPrinted, .sortedKeys]
).write(to: metadata)
