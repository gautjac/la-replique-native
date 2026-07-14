import AppKit

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Background — charcoal desk with a soft vertical gradient (desk → slightly lifted).
let cs = CGColorSpaceCreateDeviceRGB()
func rgb(_ r: Int,_ g: Int,_ b: Int,_ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat(r)/255, CGFloat(g)/255, CGFloat(b)/255, a])!
}
let grad = CGGradient(colorsSpace: cs,
    colors: [rgb(0x22,0x27,0x33), rgb(0x14,0x17,0x1e)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

// A subtle centre glow behind the marks.
let glow = CGGradient(colorsSpace: cs,
    colors: [rgb(0x4f,0x7c,0xff,0.16), rgb(0x4f,0x7c,0xff,0)] as CFArray,
    locations: [0,1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S/2, y: S/2), startRadius: 0,
                       endCenter: CGPoint(x: S/2, y: S/2), endRadius: S*0.5, options: [])

// Two guillemets « » — dialogue, la réplique. Left gel-blue, right teal.
func chevron(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, thick: CGFloat, pointRight: Bool, color: CGColor) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(thick)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let dir: CGFloat = pointRight ? 1 : -1
    let p = CGMutablePath()
    p.move(to: CGPoint(x: cx - dir*w/2, y: cy + h/2))
    p.addLine(to: CGPoint(x: cx + dir*w/2, y: cy))
    p.addLine(to: CGPoint(x: cx - dir*w/2, y: cy - h/2))
    ctx.addPath(p); ctx.strokePath()
}

let cy = S/2
let w: CGFloat = 150, h: CGFloat = 300, thick: CGFloat = 74
let gel  = rgb(0x4f,0x7c,0xff)
let teal = rgb(0x14,0xc0,0xd8)
// « (left, pointing left) — two chevrons
chevron(cx: S*0.30, cy: cy, w: w, h: h, thick: thick, pointRight: false, color: gel)
chevron(cx: S*0.30 + 118, cy: cy, w: w, h: h, thick: thick, pointRight: false, color: gel)
// » (right, pointing right)
chevron(cx: S*0.70 - 118, cy: cy, w: w, h: h, thick: thick, pointRight: true, color: teal)
chevron(cx: S*0.70, cy: cy, w: w, h: h, thick: thick, pointRight: true, color: teal)

img.unlockFocus()

let dst = CommandLine.arguments[1]
let tiff = img.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: dst))
print("wrote \(dst)")
