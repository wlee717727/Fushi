// 用系統內建的 WebKit 把 SVG 轉成 PNG (支援陰影、光暈等濾鏡效果)。
// 用法：swift scripts/render-svg.swift <輸入.svg> <輸出.png> <寬> <高>
import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count >= 5, let w = Double(args[3]), let h = Double(args[4]) else {
    print("用法：render-svg.swift <輸入.svg> <輸出.png> <寬> <高>"); exit(1)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])

final class Renderer: NSObject, WKNavigationDelegate {
    let web: WKWebView
    init(size: CGSize) {
        let config = WKWebViewConfiguration()
        web = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        super.init()
        web.navigationDelegate = self
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 等一下讓濾鏡畫完
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let config = WKSnapshotConfiguration()
            config.rect = webView.bounds
            config.snapshotWidth = NSNumber(value: Double(webView.bounds.width))
            webView.takeSnapshot(with: config) { image, error in
                guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    print("轉檔失敗：\(String(describing: error))"); exit(2)
                }
                try? png.write(to: output)
                print("已轉成 PNG：\(output.path) (\(rep.pixelsWide)×\(rep.pixelsHigh))")
                exit(0)
            }
        }
    }
}

let app = NSApplication.shared
let renderer = Renderer(size: CGSize(width: w, height: h))
let svg = (try? String(contentsOf: input, encoding: .utf8)) ?? ""
let html = "<html><head><style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}svg{display:block;width:\(Int(w))px;height:\(Int(h))px}</style></head><body>\(svg)</body></html>"
renderer.web.loadHTMLString(html, baseURL: nil)
DispatchQueue.main.asyncAfter(deadline: .now() + 15) { print("轉檔逾時"); exit(3) }
app.run()
