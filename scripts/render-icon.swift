import AppKit

func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF)/255, green: CGFloat((v >> 8) & 0xFF)/255, blue: CGFloat(v & 0xFF)/255, alpha: 1)
}

let canvas = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Big Sur grid: 824x824-ish squircle centered on 1024. Measured off the real Music icon:
// 816pt extent, corner profile matching a plain rounded rect at r=170.
let squircle = NSRect(x: 104, y: 104, width: 816, height: 816)
let path = NSBezierPath(roundedRect: squircle, xRadius: 170, yRadius: 170)

// Shadow pass, matched to the alpha falloff under the real icon's bottom edge.
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
shadow.shadowOffset = NSSize(width: 0, height: -6)
shadow.shadowBlurRadius = 18
shadow.set()
hex(0xFF0643).setFill()
path.fill()
NSGraphicsContext.current?.restoreGraphicsState()

// Sampled from /System/Applications/Music.app on macOS 27: #FF5577 top -> #FF0643 bottom.
NSGradient(starting: hex(0xFF5577), ending: hex(0xFF0643))!.draw(in: path, angle: -90)

// The lyric glyph the menu bar item uses, in white like Music's note.
let cfg = NSImage.SymbolConfiguration(pointSize: 400, weight: .medium)
    .applying(.init(paletteColors: [.white]))
guard let symbol = NSImage(systemSymbolName: "music.note.list", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) else { fatalError("no symbol") }
let targetWidth: CGFloat = 460
let scale = targetWidth / symbol.size.width
let drawSize = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
let drawRect = NSRect(x: (1024 - drawSize.width)/2, y: (1024 - drawSize.height)/2,
                      width: drawSize.width, height: drawSize.height)
symbol.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon_1024.png"))
print("wrote icon_1024.png, symbol natural size \(symbol.size)")
