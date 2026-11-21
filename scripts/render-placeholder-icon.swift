// 產生暫時的佔位 App 圖示 (1024×1024 PNG)。
// 用法：swift scripts/render-placeholder-icon.swift <輸出路徑> <字> <上色 #RRGGBB> <下色 #RRGGBB>
// 只用系統內建的 CoreGraphics / CoreText / ImageIO，不需要安裝任何東西。
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 5 else {
    FileHandle.standardError.write("用法：render-placeholder-icon.swift <輸出.png> <字> <#上色> <#下色>\n".data(using: .utf8)!)
    exit(1)
}
let outPath = args[1]
let glyph = args[2]

func color(_ hex: String) -> CGColor {
    var s = hex.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("#") { s.removeFirst() }
    let v = UInt32(s, radix: 16) ?? 0x336655
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(2) }

// Apple 的 macOS 圖示格線：1024 畫布裡，主體約 824×824，四周留白 100。
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let path = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// 底下的柔和陰影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.28))
ctx.addPath(path)
ctx.setFillColor(color(args[3]))
ctx.fillPath()
ctx.restoreGState()

// 上下漸層
ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let gradient = CGGradient(colorsSpace: space, colors: [color(args[3]), color(args[4])] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.restoreGState()

// 中央的字
let font = CTFontCreateWithName("PingFangTC-Semibold" as CFString, 470, nil)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: CGColor(gray: 1, alpha: 0.96),
]
let line = CTLineCreateWithAttributedString(NSAttributedString(string: glyph, attributes: attrs))
let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
ctx.textPosition = CGPoint(x: 512 - bounds.width / 2 - bounds.minX, y: 512 - bounds.height / 2 - bounds.minY)
CTLineDraw(line, ctx)

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else { exit(3) }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { exit(4) }
print("已產生佔位圖示：\(outPath)")
