// Draws the Overtime app icon and writes it as a 1024 px PNG.
// Usage: swift scripts/make-icon.swift <output.png>   (see scripts/make-icon.sh)
// Original artwork: a clock whose hand has run past the hour, with the extra
// stretch marked in orange. No third-party or Apple artwork is used.
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
let space = CGColorSpaceCreateDeviceRGB()
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r / 255, g / 255, b / 255, a])!
}

// Rounded tile with the usual margin around it, and a soft shadow.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35))
context.addPath(tilePath)
context.setFillColor(color(18, 22, 46))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tilePath)
context.clip()
let background = CGGradient(colorsSpace: space, colors: [color(44, 52, 110), color(14, 16, 36)] as CFArray,
                            locations: [0, 1])!
context.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
context.restoreGState()

let center = CGPoint(x: 512, y: 512)
let radius: CGFloat = 262
func point(angle degrees: CGFloat, distance: CGFloat) -> CGPoint {
    // 0 degrees is 12 o'clock, growing clockwise.
    let radians = (90 - degrees) * .pi / 180
    return CGPoint(x: center.x + cos(radians) * distance, y: center.y + sin(radians) * distance)
}

// Dial ring.
context.setLineCap(.round)
context.setStrokeColor(color(255, 255, 255, 0.92))
context.setLineWidth(40)
context.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
context.strokePath()

// Hour marks.
context.setLineWidth(18)
for hour in 0..<12 where hour % 3 != 0 {
    let a = CGFloat(hour) * 30
    context.move(to: point(angle: a, distance: radius - 62))
    context.addLine(to: point(angle: a, distance: radius - 44))
}
context.strokePath()
context.setLineWidth(24)
for hour in stride(from: 0, to: 12, by: 3) {
    let a = CGFloat(hour) * 30
    context.move(to: point(angle: a, distance: radius - 78))
    context.addLine(to: point(angle: a, distance: radius - 44))
}
context.strokePath()

// The extra time: an orange stretch from 12 to 3 o'clock on the ring.
let overtime: CGFloat = 90
context.setStrokeColor(color(255, 149, 0))
context.setLineWidth(56)
context.addArc(center: center, radius: radius, startAngle: .pi / 2,
               endAngle: (90 - overtime) * .pi / 180, clockwise: true)
context.strokePath()

// Hands: the hour hand still at 12, the minute hand at the end of the orange stretch.
context.setStrokeColor(color(255, 255, 255))
context.setLineWidth(34)
context.move(to: center)
context.addLine(to: point(angle: 0, distance: 128))
context.strokePath()
context.setStrokeColor(color(255, 149, 0))
context.setLineWidth(28)
context.move(to: center)
context.addLine(to: point(angle: overtime, distance: 178))
context.strokePath()
context.setFillColor(color(255, 255, 255))
context.fillEllipse(in: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))

try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
