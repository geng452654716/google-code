import AppKit

private let canvas = CGFloat(1024)
private let output = CommandLine.arguments.dropFirst().first ?? "assets/branding/totp_vault_icon_1024.png"

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
  NSColor(
    calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
    green: CGFloat((hex >> 8) & 0xff) / 255,
    blue: CGFloat(hex & 0xff) / 255,
    alpha: alpha
  )
}

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
  fatalError("Unable to create drawing context")
}
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

let tileRect = NSRect(x: 52, y: 52, width: 920, height: 920)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 224, yRadius: 224)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 42
shadow.shadowOffset = NSSize(width: 0, height: -24)
shadow.set()
color(0x312E81).setFill()
tile.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
tile.addClip()
let background = NSGradient(colorsAndLocations:
  (color(0x06B6D4), 0.0),
  (color(0x2563EB), 0.42),
  (color(0x6D28D9), 1.0)
)!
background.draw(in: tile, angle: -48)

let glow = NSGradient(starting: NSColor.white.withAlphaComponent(0.34), ending: NSColor.white.withAlphaComponent(0))!
glow.draw(
  fromCenter: NSPoint(x: 330, y: 770),
  radius: 0,
  toCenter: NSPoint(x: 330, y: 770),
  radius: 610,
  options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation]
)

let lowerShade = NSGradient(starting: NSColor.clear, ending: color(0x1E1B4B, alpha: 0.34))!
lowerShade.draw(in: tileRect, angle: 90)
NSGraphicsContext.restoreGraphicsState()

let shield = NSBezierPath()
shield.move(to: NSPoint(x: 512, y: 805))
shield.curve(to: NSPoint(x: 286, y: 711), controlPoint1: NSPoint(x: 438, y: 770), controlPoint2: NSPoint(x: 360, y: 742))
shield.line(to: NSPoint(x: 286, y: 528))
shield.curve(to: NSPoint(x: 512, y: 223), controlPoint1: NSPoint(x: 286, y: 379), controlPoint2: NSPoint(x: 377, y: 280))
shield.curve(to: NSPoint(x: 738, y: 528), controlPoint1: NSPoint(x: 647, y: 280), controlPoint2: NSPoint(x: 738, y: 379))
shield.line(to: NSPoint(x: 738, y: 711))
shield.curve(to: NSPoint(x: 512, y: 805), controlPoint1: NSPoint(x: 664, y: 742), controlPoint2: NSPoint(x: 586, y: 770))
shield.close()

NSGraphicsContext.saveGraphicsState()
let shieldShadow = NSShadow()
shieldShadow.shadowColor = color(0x172554, alpha: 0.3)
shieldShadow.shadowBlurRadius = 28
shieldShadow.shadowOffset = NSSize(width: 0, height: -14)
shieldShadow.set()
NSColor.white.withAlphaComponent(0.16).setFill()
shield.fill()
NSGraphicsContext.restoreGraphicsState()

NSColor.white.withAlphaComponent(0.94).setStroke()
shield.lineWidth = 34
shield.lineJoinStyle = .round
shield.stroke()

let dotCenters: [NSPoint] = [
  NSPoint(x: 421, y: 579), NSPoint(x: 512, y: 579), NSPoint(x: 603, y: 579),
  NSPoint(x: 421, y: 478), NSPoint(x: 512, y: 478), NSPoint(x: 603, y: 478),
]
for (index, center) in dotCenters.enumerated() {
  let radius = CGFloat(index == 4 ? 31 : 27)
  let circle = NSBezierPath(ovalIn: NSRect(
    x: center.x - radius,
    y: center.y - radius,
    width: radius * 2,
    height: radius * 2
  ))
  (index == 4 ? color(0xCFFAFE) : NSColor.white).setFill()
  circle.fill()
}

let keyStem = NSBezierPath(roundedRect: NSRect(x: 495, y: 382, width: 34, height: 72), xRadius: 17, yRadius: 17)
color(0xCFFAFE).setFill()
keyStem.fill()

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
  fatalError("Unable to encode icon PNG")
}
let outputURL = URL(fileURLWithPath: output)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: outputURL)
print(outputURL.path)
