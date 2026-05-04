#!/usr/bin/env swift

import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()

guard let context = NSGraphicsContext.current else {
    fatalError("Failed to get graphics context")
}
context.imageInterpolation = .high
context.shouldAntialias = true

// --- Rounded rectangle background with purple gradient ---
let cornerRadius: CGFloat = 220
let bgRect = NSRect(origin: .zero, size: size)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

// Purple/magenta gradient matching Proton Mail branding
let topColor    = NSColor(calibratedRed: 0.42, green: 0.16, blue: 0.87, alpha: 1.0) // vivid purple
let bottomColor = NSColor(calibratedRed: 0.70, green: 0.22, blue: 0.72, alpha: 1.0) // magenta-pink

guard let gradient = NSGradient(starting: bottomColor, ending: topColor) else {
    fatalError("Failed to create gradient")
}
gradient.draw(in: bgPath, angle: 90)

// Subtle inner shadow / border for depth
let borderPath = NSBezierPath(roundedRect: bgRect.insetBy(dx: 4, dy: 4), xRadius: cornerRadius - 4, yRadius: cornerRadius - 4)
borderPath.lineWidth = 3
NSColor(white: 1.0, alpha: 0.12).setStroke()
borderPath.stroke()

// --- White envelope icon ---
let envelopeColor = NSColor.white

// Envelope body dimensions (centered)
let envW: CGFloat = 560
let envH: CGFloat = 400
let envX: CGFloat = (1024 - envW) / 2
let envY: CGFloat = (1024 - envH) / 2 - 20  // slightly below center for visual balance

let envRect = NSRect(x: envX, y: envY, width: envW, height: envH)

// Envelope body - rounded rectangle
let envBodyPath = NSBezierPath(roundedRect: envRect, xRadius: 30, yRadius: 30)
envelopeColor.setFill()
envBodyPath.fill()

// Envelope flap (V-shape from top corners to center)
let flapPath = NSBezierPath()
let flapTopY = envY + envH
let flapPeakY = envY + envH * 0.42  // how deep the V goes

flapPath.move(to: NSPoint(x: envX, y: flapTopY))
flapPath.line(to: NSPoint(x: envX + envW / 2, y: flapPeakY))
flapPath.line(to: NSPoint(x: envX + envW, y: flapTopY))
flapPath.close()

// Draw flap with a slightly darker shade for contrast
NSColor(white: 1.0, alpha: 0.85).setFill()
flapPath.fill()

// Flap outline for definition
flapPath.lineWidth = 6
NSColor(calibratedRed: 0.42, green: 0.16, blue: 0.87, alpha: 0.35).setStroke()
flapPath.stroke()

// Bottom V-lines on envelope body (the fold lines)
let foldPath = NSBezierPath()
foldPath.move(to: NSPoint(x: envX, y: envY))
foldPath.line(to: NSPoint(x: envX + envW / 2, y: envY + envH * 0.50))
foldPath.line(to: NSPoint(x: envX + envW, y: envY))
foldPath.lineWidth = 6
NSColor(calibratedRed: 0.42, green: 0.16, blue: 0.87, alpha: 0.18).setStroke()
foldPath.stroke()

// --- Small shield / lock accent (Proton security feel) ---
// A tiny shield in the bottom-right of the envelope
let shieldCX: CGFloat = envX + envW - 60
let shieldCY: CGFloat = envY + 50
let shieldW: CGFloat = 70
let shieldH: CGFloat = 85

let shieldPath = NSBezierPath()
shieldPath.move(to: NSPoint(x: shieldCX, y: shieldCY + shieldH / 2))
// top-left curve
shieldPath.curve(to: NSPoint(x: shieldCX - shieldW / 2, y: shieldCY + shieldH * 0.25),
                 controlPoint1: NSPoint(x: shieldCX - shieldW * 0.35, y: shieldCY + shieldH / 2),
                 controlPoint2: NSPoint(x: shieldCX - shieldW / 2, y: shieldCY + shieldH * 0.4))
// left side down
shieldPath.line(to: NSPoint(x: shieldCX - shieldW / 2, y: shieldCY))
// bottom point
shieldPath.curve(to: NSPoint(x: shieldCX, y: shieldCY - shieldH / 2),
                 controlPoint1: NSPoint(x: shieldCX - shieldW / 2, y: shieldCY - shieldH * 0.25),
                 controlPoint2: NSPoint(x: shieldCX - shieldW * 0.15, y: shieldCY - shieldH * 0.4))
shieldPath.curve(to: NSPoint(x: shieldCX + shieldW / 2, y: shieldCY),
                 controlPoint1: NSPoint(x: shieldCX + shieldW * 0.15, y: shieldCY - shieldH * 0.4),
                 controlPoint2: NSPoint(x: shieldCX + shieldW / 2, y: shieldCY - shieldH * 0.25))
// right side up
shieldPath.line(to: NSPoint(x: shieldCX + shieldW / 2, y: shieldCY + shieldH * 0.25))
// top-right curve
shieldPath.curve(to: NSPoint(x: shieldCX, y: shieldCY + shieldH / 2),
                 controlPoint1: NSPoint(x: shieldCX + shieldW / 2, y: shieldCY + shieldH * 0.4),
                 controlPoint2: NSPoint(x: shieldCX + shieldW * 0.35, y: shieldCY + shieldH / 2))
shieldPath.close()

// Shield fill - purple accent
NSColor(calibratedRed: 0.50, green: 0.18, blue: 0.85, alpha: 1.0).setFill()
shieldPath.fill()

// Checkmark inside shield
let checkPath = NSBezierPath()
checkPath.move(to: NSPoint(x: shieldCX - 16, y: shieldCY + 2))
checkPath.line(to: NSPoint(x: shieldCX - 4, y: shieldCY - 12))
checkPath.line(to: NSPoint(x: shieldCX + 18, y: shieldCY + 16))
checkPath.lineWidth = 8
checkPath.lineCapStyle = .round
checkPath.lineJoinStyle = .round
NSColor.white.setStroke()
checkPath.stroke()

image.unlockFocus()

// --- Save as PNG ---
guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to create PNG data")
}

let outputPath = "/tmp/protonkit_icon_1024.png"
let url = URL(fileURLWithPath: outputPath)
try! pngData.write(to: url)
print("Icon saved to \(outputPath)")
