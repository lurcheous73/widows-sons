// Run from mobile/: swift tool/generate_icons.swift
// A temporary WS monogram, not an invented official chapter badge.
import AppKit
import Foundation
import ImageIO

func drawIcon(_ pixels: Int, to path: String) throws {
  let bitmap = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
    bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  let context = NSGraphicsContext(cgContext: bitmap, flipped: false)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
  NSColor(srgbRed: 17/255, green: 24/255, blue: 32/255, alpha: 1).setFill()
  NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
  let gold = NSColor(srgbRed: 197/255, green: 163/255, blue: 101/255, alpha: 1)
  gold.withAlphaComponent(0.15).setStroke()
  let road = NSBezierPath()
  road.move(to: NSPoint(x: 1000, y: -50))
  road.curve(to: NSPoint(x: 820, y: 1060), controlPoint1: NSPoint(x: 400, y: 300), controlPoint2: NSPoint(x: 1160, y: 750))
  road.lineWidth = 100
  road.stroke()
  gold.setStroke()
  let border = NSBezierPath(roundedRect: NSRect(x: 110, y: 110, width: 804, height: 804), xRadius: 180, yRadius: 180)
  border.lineWidth = 5
  border.stroke()
  let font = NSFont(name: "Georgia", size: 300) ?? NSFont.systemFont(ofSize: 300, weight: .semibold)
  let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: gold]
  let text = "WS" as NSString
  let width = text.size(withAttributes: attrs).width
  text.draw(at: NSPoint(x: (1024 - width) / 2, y: 390), withAttributes: attrs)
  let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 62, weight: .medium), .foregroundColor: gold, .kern: 16]
  let chapter = "L&R" as NSString
  chapter.draw(at: NSPoint(x: (1024 - chapter.size(withAttributes: small).width) / 2, y: 290), withAttributes: small)
  NSGraphicsContext.restoreGraphicsState()
  let output = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
  CGImageDestinationAddImage(output, bitmap.makeImage()!, nil)
  guard CGImageDestinationFinalize(output) else { throw NSError(domain: "IconExport", code: 1) }
}

let directory = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: directory + "/Contents.json"))) as! [String: Any]
for item in json["images"] as! [[String: String]] {
  let points = Double(item["size"]!.split(separator: "x")[0])!
  let scale = Double(item["scale"]!.dropLast())!
  try drawIcon(Int(points * scale), to: directory + "/" + item["filename"]!)
}
for (density, pixels) in [("mdpi",48),("hdpi",72),("xhdpi",96),("xxhdpi",144),("xxxhdpi",192)] {
  try drawIcon(pixels, to: "android/app/src/main/res/mipmap-\(density)/ic_launcher.png")
}
print("Widows Sons monogram icons generated for iOS and Android.")
