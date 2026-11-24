// アプリのアイコンと、同じ絵を 1 色にした印を描いて、Assets.xcassets に書き出す。
// 使い方: make icon（プロジェクトのフォルダで。swift scripts/make-app-icon.swift でも動く）
//
// デザイン: 左のストリップと、ステージに横に並べた 2 枚のウインドウ。手前のウインドウを赤いピンで留める（Pin + Stage）。
// 上からスポットライトのような淡い光を当てて、「ステージ」に見せる。
// 背景は紫のグラデーションの角丸の四角。作りは Pinshot・Pinshelf のアイコンにそろえ（白いものを赤いピンで留める）、
// 色で見分けられるようにする（Pinshot は青、Pinshelf はオレンジ）。
//
// 書き出すもの（アイコンを出すところは、すべてこのどちらかを使う）
// - AppIcon.appiconset: アプリのアイコン（色付き）。Finder・Dock・ログイン項目など
// - AppSymbol.imageset: アプリの印（1 色の PDF。テンプレート画像）。メニューバー
import AppKit

let catalogDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Pinstage/Assets.xcassets")
let outputDir = catalogDir.appendingPathComponent("AppIcon.appiconset")
let symbolDir = catalogDir.appendingPathComponent("AppSymbol.imageset")

// MARK: - 色

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func gradient(_ colors: [CGColor], locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

/// 影の色（背景の紫を濃くした色）
let shadowColor: UInt32 = 0x24104F
/// ウインドウの中の線・題の帯の色（背景の紫を薄くした色）
let lineColor: UInt32 = 0xD9CFF7
let titleBarColor: UInt32 = 0xEEE8FD

// MARK: - 描く（1024 × 1024 の座標で描き、サイズに合わせて縮める。原点は左下）

func drawIcon(in ctx: CGContext) {
    // macOS のアイコンの決まり: 1024 の中に 824 の角丸の四角（まわりは影のための余白）
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // 本体の影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(rgb(0x6A3FD6))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    // 背景のグラデーション（上が明るい紫、下が濃い紫）
    ctx.drawLinearGradient(
        gradient([rgb(0x9C7BFF), rgb(0x5530C4)]),
        start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: []
    )
    // スポットライト（上の真ん中から、ステージへ広がる淡い光）
    let light = CGMutablePath()
    light.move(to: CGPoint(x: 470, y: body.maxY))
    light.addLine(to: CGPoint(x: 600, y: body.maxY))
    // 下の端で線が見えないよう、本体の下まで伸ばして、だんだん消す
    light.addLine(to: CGPoint(x: 1010, y: body.minY))
    light.addLine(to: CGPoint(x: 140, y: body.minY))
    light.closeSubpath()
    ctx.saveGState()
    ctx.addPath(light)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([rgb(0xFFFFFF, 0.30), rgb(0xFFFFFF, 0.08), rgb(0xFFFFFF, 0)], locations: [0, 0.6, 1]),
        start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY + 60), options: []
    )
    ctx.restoreGState()
    // ステージの床（ウインドウの下に、淡い楕円の光だまり）
    ctx.drawRadialGradient(
        gradient([rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)]),
        startCenter: CGPoint(x: 585, y: 250), startRadius: 0,
        endCenter: CGPoint(x: 585, y: 250), endRadius: 300,
        options: []
    )
    ctx.restoreGState()

    drawStrip(in: ctx)
    // 奥のウインドウ・手前のウインドウ（手前を少し重ねて、比べている様子にする）
    drawWindow(in: ctx, rect: CGRect(x: 318, y: 316, width: 288, height: 380), colors: [rgb(0xFBF9FF), rgb(0xEDE6FD)], pinned: false)
    drawWindow(in: ctx, rect: CGRect(x: 574, y: 290, width: 296, height: 400), colors: [rgb(0xFFFFFF), rgb(0xF3EEFE)], pinned: true)
}

/// 左のストリップ（すりガラスの帯と、小さなタイル 3 つ。いちばん上のタイルは選んでいる色）
func drawStrip(in ctx: CGContext) {
    let strip = CGRect(x: 172, y: 262, width: 114, height: 500)
    let path = CGPath(roundedRect: strip, cornerWidth: 36, cornerHeight: 36, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(shadowColor, 0.3))
    ctx.addPath(path)
    ctx.setFillColor(rgb(0xFFFFFF, 0.32))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(path)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.45))
    ctx.setLineWidth(3)
    ctx.strokePath()

    let tileSize: CGFloat = 70
    for (index, top) in [CGFloat(722), 612, 502].enumerated() {
        let tile = CGRect(x: strip.midX - tileSize / 2, y: top - tileSize, width: tileSize, height: tileSize)
        let tilePath = CGPath(roundedRect: tile, cornerWidth: 18, cornerHeight: 18, transform: nil)
        ctx.addPath(tilePath)
        // いちばん上はステージに出しているもの（白く、はっきり）
        ctx.setFillColor(rgb(0xFFFFFF, index == 0 ? 0.95 : 0.6))
        ctx.fillPath()
    }
}

/// ウインドウ（題の帯と、中の線）。pinned なら上の辺の真ん中を赤いピンで留める
func drawWindow(in ctx: CGContext, rect: CGRect, colors: [CGColor], pinned: Bool) {
    let path = CGPath(roundedRect: rect, cornerWidth: 34, cornerHeight: 34, transform: nil)
    // 紙（影を付けて浮かせる）
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(shadowColor, 0.42))
    ctx.addPath(path)
    ctx.setFillColor(colors[0])
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient(colors),
        start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: []
    )
    // 題の帯
    ctx.setFillColor(rgb(titleBarColor))
    ctx.fill(CGRect(x: rect.minX, y: rect.maxY - 64, width: rect.width, height: 64))
    ctx.restoreGState()

    // 中の線（左にそろえて 3 本）
    ctx.setFillColor(rgb(lineColor))
    for (top, ratio) in [(CGFloat(110), CGFloat(0.66)), (CGFloat(166), CGFloat(0.5)), (CGFloat(222), CGFloat(0.58))] {
        let line = CGRect(x: rect.minX + 40, y: rect.maxY - top - 24, width: (rect.width - 80) * ratio, height: 24)
        ctx.addPath(CGPath(roundedRect: line, cornerWidth: 12, cornerHeight: 12, transform: nil))
        ctx.fillPath()
    }

    if pinned {
        drawPin(in: ctx, at: CGPoint(x: rect.midX, y: rect.maxY - 8))
    }
}

/// 赤いピン（Pinshot・Pinshelf と同じ色と作り）
func drawPin(in ctx: CGContext, at center: CGPoint) {
    let r: CGFloat = 48
    let head = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
    // 頭と、その影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 5, height: -10), blur: 12, color: rgb(0x000000, 0.35))
    ctx.setFillColor(rgb(0xE5484D))
    ctx.fillEllipse(in: head)
    ctx.restoreGState()
    // 頭の立体感
    ctx.saveGState()
    ctx.addEllipse(in: head)
    ctx.clip()
    ctx.drawRadialGradient(
        gradient([rgb(0xFF7A7E), rgb(0xC9282E)]),
        startCenter: CGPoint(x: center.x - 16, y: center.y + 18), startRadius: 4,
        endCenter: center, endRadius: r + 6,
        options: [.drawsAfterEndLocation]
    )
    ctx.restoreGState()
    // 光の点
    ctx.setFillColor(rgb(0xFFFFFF, 0.75))
    ctx.fillEllipse(in: CGRect(x: center.x - 27, y: center.y + 7, width: 22, height: 17))
}

// MARK: - アプリの印（1 色。メニューバーに出す）

/// アプリの印の形。アイコンと同じストリップ・2 枚のウインドウ・ピンを、1 色の形にしたもの。
/// 重なるところ（ウインドウどうし・ウインドウとピン）は、すき間を空けて見分けられるようにする。
/// 座標は 100 × 100 くらい（原点は左下）。書き出すときに、枠いっぱいに収める
func symbolPath() -> CGPath {
    /// すき間の幅
    let gap: CGFloat = 5

    /// path を、まわりに gap だけ広げた形（重なるところを抜くのに使う）
    func clearance(_ path: CGPath) -> CGPath {
        path.union(path.copy(strokingWithWidth: gap * 2, lineCap: .round, lineJoin: .round, miterLimit: 1))
    }

    // ストリップ（細い帯）
    let strip = CGPath(roundedRect: CGRect(x: 2, y: 20, width: 12, height: 60), cornerWidth: 5, cornerHeight: 5, transform: nil)
    // 2 枚のウインドウ（小さく縮めても 2 枚に見えるよう、重ねずに並べる。ピンを留める右のほうを少し大きく）
    let back = CGPath(roundedRect: CGRect(x: 21, y: 26, width: 34, height: 50), cornerWidth: 6, cornerHeight: 6, transform: nil)
    let frontRect = CGRect(x: 61, y: 22, width: 37, height: 56)
    let front = CGPath(roundedRect: frontRect, cornerWidth: 6, cornerHeight: 6, transform: nil)

    // ピン（手前のウインドウの内側の上の方に、まわりにすき間を空けて置く。上の辺からはみ出すと、人の頭に見えるため）
    let pinCenter = CGPoint(x: frontRect.midX, y: frontRect.maxY - 12)
    let pinRect = CGRect(x: pinCenter.x - 5.5, y: pinCenter.y - 5.5, width: 11, height: 11)
    let pin = CGPath(ellipseIn: pinRect, transform: nil)
    let pinRing = CGPath(ellipseIn: pinRect.insetBy(dx: -gap * 0.8, dy: -gap * 0.8), transform: nil)

    let frontWindow = front.subtracting(pinRing).union(pin)
    // 奥のウインドウは、手前のウインドウのまわりを抜く
    let backWindow = back.subtracting(clearance(front))
    return strip.union(backWindow).union(frontWindow)
}

/// アプリの印を、size × size（ポイント）の PDF にする。まわりに margin の余白を残して、真ん中に収める
func symbolPDF(size: CGFloat, margin: CGFloat) -> Data {
    let path = symbolPath()
    let bounds = path.boundingBoxOfPath
    let scale = min((size - margin * 2) / bounds.width, (size - margin * 2) / bounds.height)
    var fit = CGAffineTransform(translationX: size / 2, y: size / 2)
        .scaledBy(x: scale, y: scale)
        .translatedBy(x: -bounds.midX, y: -bounds.midY)
    let fitted = path.copy(using: &fit)!

    let data = NSMutableData()
    var mediaBox = CGRect(x: 0, y: 0, width: size, height: size)
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
    pdf.beginPDFPage(nil)
    pdf.addPath(fitted)
    pdf.setFillColor(CGColor(gray: 0, alpha: 1))
    pdf.fillPath()
    pdf.endPDFPage()
    pdf.closePDF()
    return data as Data
}

// MARK: - 書き出す

func png(size: Int) -> Data? {
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    let scale = CGFloat(size) / 1024
    ctx.scaleBy(x: scale, y: scale)
    drawIcon(in: ctx)
    guard let image = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
}

// macOS が求める大きさ（ポイント × 倍率）
let entries: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
var images: [[String: String]] = []
for entry in entries {
    let pixels = entry.points * entry.scale
    let name = "icon_\(entry.points)x\(entry.points)\(entry.scale == 2 ? "@2x" : "").png"
    guard let data = png(size: pixels) else { fatalError("描けませんでした: \(name)") }
    try data.write(to: outputDir.appendingPathComponent(name))
    images.append([
        "idiom": "mac",
        "size": "\(entry.points)x\(entry.points)",
        "scale": "\(entry.scale)x",
        "filename": name,
    ])
}

let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDir.appendingPathComponent("Contents.json"))

// アプリの印（メニューバーのアイコンと同じ 18 ポイント。ベクターのまま持つ）
try FileManager.default.createDirectory(at: symbolDir, withIntermediateDirectories: true)
try symbolPDF(size: 18, margin: 1).write(to: symbolDir.appendingPathComponent("AppSymbol.pdf"))
let symbolContents: [String: Any] = [
    "images": [["idiom": "universal", "filename": "AppSymbol.pdf"]],
    "info": ["version": 1, "author": "xcode"],
    // テンプレート画像にする（メニューバーの明るさ・押したとき・文字の色に合わせて、macOS が色を付ける）
    "properties": ["preserves-vector-representation": true, "template-rendering-intent": "template"],
]
let symbolJSON = try JSONSerialization.data(withJSONObject: symbolContents, options: [.prettyPrinted, .sortedKeys])
try symbolJSON.write(to: symbolDir.appendingPathComponent("Contents.json"))

// アセットカタログ自体の Contents.json
let catalogContents = try JSONSerialization.data(withJSONObject: ["info": ["version": 1, "author": "xcode"]], options: [.prettyPrinted, .sortedKeys])
try catalogContents.write(to: catalogDir.appendingPathComponent("Contents.json"))

print("書き出しました: \(outputDir.path)、\(symbolDir.path)")
