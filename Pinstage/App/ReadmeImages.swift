#if DEBUG
import AppKit
import PinstageCore
import SwiftUI
import UniformTypeIdentifiers

/// 開発用: README に載せる見本の画像を作る（make readme-images が動かす。docs/images に書き出す）
///
/// ウインドウバーとウインドウスイッチャーは、アプリと同じ部品に見本のデータ（StripPreview と同じ）を入れて描き、
/// 架空のデスクトップの上に並べる。デスクトップ・ほかのアプリのウインドウ・カーソルは絵として描く（自分の画面や、個人の情報は写さない）。
/// ウインドウバーの置き場所・ステージの範囲・ウインドウの並べ方は、アプリと同じ計算（StripGeometry・LayoutChoice・StageLayout）で決める。
/// 見た目は Pinshelf・Pinshot の README の画像にそろえる（明るい見た目・同じ壁紙とメニューバー）。
///
/// - hero.png: 全体の見本（左のウインドウバーと、ステージに並べた 2 つのウインドウ）
/// - arrange.gif: 行のクリックでそのウインドウだけを出す → ⌘＋クリックで横に足す
/// - switcher.png: ウインドウスイッチャー（⌥Tab）
enum ReadmeImages {
    /// 2 倍の画素で描く（PNG はそのまま、GIF は 1 倍にして軽くする）
    private static let scale: CGFloat = 2

    static func render(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        StripPreview.withSample(scenario: .desktopList) { sample in
            sample.stage.stripSettings.itemSize = .list
            sample.stage.stripSettings.mode = .alwaysShown
            sample.stage.stripSettings.edge = .left
            let scene = Scene(sample: sample)
            write("hero.png", folder) { try writePNG(scene.hero(), to: $0) }
            write("arrange.gif", folder) { try writeGIF(scene.arrange(), to: $0) }
            write("switcher.png", folder) { try writePNG(scene.switcher(), to: $0) }
        }
    }

    private static func write(_ name: String, _ folder: URL, _ body: (URL) throws -> Void) {
        do {
            try body(folder.appending(path: name))
            print("書き出しました: \(name)")
        } catch {
            FileHandle.standardError.write(Data("\(name) を作れませんでした: \(error)\n".utf8))
        }
    }

    // MARK: - 見本の場面

    /// ステージに出したウインドウ（枠と濃さ。出てくる途中は薄い）
    private typealias Placed = (item: WindowItem, frame: CGRect, alpha: CGFloat)

    /// 架空のデスクトップでの、ウインドウバーとステージの枠（アプリと同じ計算）
    private struct Desk {
        let size: CGSize
        let strip: CGRect
        let stage: CGRect

        init(size: CGSize, settings: StripSettings) {
            self.size = size
            let visible = Canvas.visibleFrame(in: size)
            strip = StripGeometry.shownFrame(in: visible, edge: settings.edge, thickness: settings.effectiveThickness)
            stage = StripGeometry.stageFrame(in: visible, mode: settings.mode, edge: settings.edge,
                                             thickness: settings.effectiveThickness, gap: settings.stageGap)
        }

        /// ステージに並べたときの枠（アプリと同じ並べ方。1 枚なら「1 枚だけ出すときの大きさ」の初期設定で、いまの幅のまま縦いっぱい）
        func frames(for count: Int) -> [CGRect] {
            // 並べ方は上が原点の座標（アクセシビリティの座標）で計算するので、ステージの真ん中で上下を折り返して渡し、戻す
            let flip = { ScreenCoordinates.toAccessibility($0, primaryScreenHeight: stage.maxY + stage.minY) }
            let area = flip(stage)
            let frames = count == 1
                ? [StageLayout.singleFrame(current: area.insetBy(dx: area.width * 0.18, dy: area.height * 0.12), in: area, size: .default)]
                : LayoutChoice.builtIn(.auto).frames(count: count, in: area, customLayouts: [])
            return frames.map(flip)
        }
    }

    /// 見本のデータを入れたウインドウバーと、ステージに出すウインドウ
    private struct Scene {
        let sample: StripPreview.Sample

        /// 描くウインドウバーのデスクトップ（見本のデスクトップ 1。Safari・メール・Finder と、すべてのデスクトップに割り当てたターミナルがある）
        static let desktop: UInt64 = 1

        /// 見本のウインドウ（StripPreview の並び: Safari・メール・Finder・メモ・カレンダー・ターミナル）
        var safari: WindowItem { sample.windows[0] }
        var finder: WindowItem { sample.windows[2] }

        func desk(_ size: CGSize) -> Desk {
            Desk(size: size, settings: sample.stage.stripSettings)
        }

        /// ウインドウバーを写す（selection: ステージに出しているウインドウ。青い枠が付く）
        func strip(selection: [WindowItem], on desk: Desk) throws -> StripShot {
            let stage = sample.stage
            stage.updateStage(on: sample.screen, apply: false) { $0.selection.replace(with: selection.map(\.id)) }
            let strip = StripController(screen: sample.screen, spaceID: Self.desktop, stage: stage,
                                        thumbnails: ThumbnailStore(), shortcuts: ShortcutCenter(), actions: AppActions())
            // このデスクトップのウインドウを並べる
            strip.spaceState.windowIDs = Set(sample.windows.filter { stage.windowSpaces?[$0.id]?.contains(Self.desktop) ?? true }.map(\.id))
            let size = desk.strip.size
            let view = StripView(stage: stage, thumbnails: ThumbnailStore(), shortcuts: ShortcutCenter(), strip: strip, actions: AppActions())
                .frame(width: size.width, height: size.height)
            guard let image = StripPreview.snapshot(view, size: size, appearance: .aqua, transparent: true)?.cgImage else {
                throw CocoaError(.fileWriteUnknown)
            }
            // 行の枠（一覧の座標）を、ウインドウバーの中身の座標（左上が原点）にする。カーソルを行に置くのに使う
            let reorder = strip.windowReorder
            let rows = reorder.frames.mapValues { $0.offsetBy(dx: reorder.listFrame.minX, dy: reorder.listFrame.minY) }
            return StripShot(image: image, frame: desk.strip, rows: rows)
        }

        /// ステージに並べた items（アプリと同じ並べ方）
        func placed(_ items: [WindowItem], on desk: Desk) -> [Placed] {
            zip(items, desk.frames(for: items.count)).map { ($0, $1, 1) }
        }

        /// デスクトップ・ステージのウインドウ・ウインドウバーを描く（メニューバーとカーソルは、その上に描く）
        func paint(_ canvas: Canvas, strip: StripShot, windows: [Placed]) {
            canvas.wallpaper()
            for window in windows {
                // Finder はファイルの並び、ほかはブラウザのページ
                canvas.appWindow(window.frame, title: window.item.title, alpha: window.alpha, content: window.item.id == finder.id ? .files : .page)
            }
            canvas.panel(strip.image, in: strip.frame, cornerRadius: 16)
        }

        // MARK: hero.png

        func hero() throws -> CGImage {
            let canvas = Canvas(size: CGSize(width: 900, height: 600), scale: ReadmeImages.scale)
            let desk = desk(canvas.size)
            let shot = try strip(selection: [safari, finder], on: desk)
            paint(canvas, strip: shot, windows: placed([safari, finder], on: desk))
            canvas.cursor(at: shot.center(ofRow: 2).applying(.init(translationX: 40, y: -4)))
            canvas.menuBar()
            return canvas.image()
        }

        // MARK: arrange.gif

        func arrange() throws -> [GIFFrame] {
            let size = CGSize(width: 760, height: 560)
            let desk = desk(size)
            let none = try strip(selection: [], on: desk)
            let one = try strip(selection: [safari], on: desk)
            let two = try strip(selection: [safari, finder], on: desk)
            let single = desk.frames(for: 1)[0]
            let pair = desk.frames(for: 2)
            let safariRow = none.center(ofRow: 0)
            let finderRow = none.center(ofRow: 2)
            var gif: [GIFFrame] = []

            /// 1 コマを描く（command: カーソルの横に ⌘ を出す）
            func frame(_ shot: StripShot, cursor: CGPoint, windows: [Placed] = [], command: Bool = false, delay: Double) {
                let canvas = Canvas(size: size, scale: ReadmeImages.scale)
                paint(canvas, strip: shot, windows: windows)
                canvas.menuBar()
                canvas.cursor(at: cursor)
                if command { canvas.key("⌘", near: cursor) }
                gif.append(GIFFrame(image: downscale(canvas.image(), by: Int(ReadmeImages.scale)), delay: delay))
            }

            // 1. 何も出していないところから、Safari の行へ
            let start = CGPoint(x: desk.stage.midX, y: desk.stage.midY - 40)
            frame(none, cursor: start, delay: 0.8)
            for step in 1...10 {
                frame(none, cursor: lerp(start, safariRow, CGFloat(step) / 10), delay: 0.04)
            }
            frame(none, cursor: safariRow, delay: 0.3)
            // 2. クリックすると、Safari だけがステージに出る
            for step in 1...5 {
                let t = CGFloat(step) / 5
                frame(one, cursor: safariRow, windows: [(safari, grow(single, from: 0.92, t), t)], delay: 0.04)
            }
            frame(one, cursor: safariRow, windows: [(safari, single, 1)], delay: 1.0)
            // 3. ⌘ を押しながら Finder の行へ
            for step in 1...8 {
                frame(one, cursor: lerp(safariRow, finderRow, CGFloat(step) / 8), windows: [(safari, single, 1)], command: true, delay: 0.04)
            }
            frame(one, cursor: finderRow, windows: [(safari, single, 1)], command: true, delay: 0.4)
            // 4. ⌘＋クリックすると、Finder を横に足して、2 つを並べる
            for step in 1...6 {
                let t = CGFloat(step) / 6
                frame(two, cursor: finderRow, windows: [(safari, lerp(single, pair[0], t), 1), (finder, grow(pair[1], from: 0.92, t), t)],
                      command: true, delay: 0.04)
            }
            frame(two, cursor: finderRow, windows: placed([safari, finder], on: desk), delay: 2.0)
            return gif
        }

        // MARK: switcher.png

        func switcher() throws -> CGImage {
            let canvas = Canvas(size: CGSize(width: 1200, height: 760), scale: ReadmeImages.scale)
            let desk = desk(canvas.size)
            let shot = try strip(selection: [safari, finder], on: desk)
            sample.stage.windowSwitcherSettings.appearance = .icons
            let preview = DesktopPickerController.preview(stage: sample.stage, screen: sample.screen)
            guard let picker = StripPreview.snapshot(preview.view, size: preview.size, appearance: .aqua, transparent: true)?.cgImage
            else { throw CocoaError(.fileWriteUnknown) }
            paint(canvas, strip: shot, windows: placed([safari, finder], on: desk))
            // アプリと同じく、ディスプレイの真ん中に開く
            let visible = Canvas.visibleFrame(in: canvas.size)
            let pickerFrame = CGRect(x: visible.midX - preview.size.width / 2, y: visible.midY - preview.size.height / 2,
                                     width: preview.size.width, height: preview.size.height)
            canvas.panel(picker, in: pickerFrame, cornerRadius: 22)
            canvas.menuBar()
            return canvas.image()
        }
    }

    // MARK: - 写したもの

    /// 写したウインドウバー（frame はキャンバスに置く枠。rows は、行の番号ごとの枠で、ウインドウバーの中身の座標・左上が原点）
    private struct StripShot {
        let image: CGImage
        let frame: CGRect
        let rows: [Int: CGRect]

        /// その行の真ん中（キャンバスの座標）
        func center(ofRow index: Int) -> CGPoint {
            guard let row = rows[index] else { return CGPoint(x: frame.midX, y: frame.midY) }
            return CGPoint(x: frame.minX + row.midX, y: frame.maxY - row.midY)
        }
    }

    private struct GIFFrame {
        let image: CGImage
        let delay: Double
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    /// 出てくるウインドウの枠（少し小さい状態から、真ん中を中心に広がる）
    private static func grow(_ rect: CGRect, from start: CGFloat, _ t: CGFloat) -> CGRect {
        let scale = start + (1 - start) * t
        return rect.insetBy(dx: rect.width * (1 - scale) / 2, dy: rect.height * (1 - scale) / 2)
    }

    // MARK: - 描く

    /// 点（pt）で描くキャンバス（scale 倍の画素で書き出す。原点は左下）
    private final class Canvas {
        static let menuBarHeight: CGFloat = 24
        /// ウインドウの上のバーの高さ
        static let titleBarHeight: CGFloat = 30

        let size: CGSize
        let context: CGContext

        init(size: CGSize, scale: CGFloat) {
            self.size = size
            context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.scaleBy(x: scale, y: scale)
            context.interpolationQuality = .high
        }

        func image() -> CGImage { context.makeImage()! }

        /// メニューバーを除いた範囲（ウインドウバーとステージを置く）
        static func visibleFrame(in size: CGSize) -> CGRect {
            CGRect(x: 0, y: 0, width: size.width, height: size.height - menuBarHeight)
        }

        /// AppKit の描き方（文字・アイコン）を使うときに、このキャンバスを今の描き先にする
        func withAppKit(_ draw: () -> Void) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            draw()
            NSGraphicsContext.restoreGraphicsState()
        }

        func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }

        func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .black) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        }

        /// デスクトップの背景（左上から右下へ色が変わる。Pinshelf と同じ色）
        func wallpaper() {
            let colors = [color(0xC9DCF6), color(0xE4D9F3)] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: nil)!
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
        }

        /// 上のメニューバー（右に Pinstage のアイコンと時計）
        func menuBar() {
            let bar = CGRect(x: 0, y: size.height - Self.menuBarHeight, width: size.width, height: Self.menuBarHeight)
            context.setFillColor(color(0xFFFFFF, 0.72))
            context.fill(bar)
            withAppKit {
                let clock = text("11月26日(水) 10:00", size: 12, weight: .medium)
                let clockSize = clock.size()
                clock.draw(at: CGPoint(x: size.width - clockSize.width - 14, y: bar.midY - clockSize.height / 2))
                // Pinstage のアイコン（メニューバーと同じ 1 色の印）
                if let symbol = AppIcon.symbol(accessibilityDescription: "Pinstage") {
                    let tinted = NSImage(size: CGSize(width: 16, height: 16), flipped: false) { rect in
                        symbol.draw(in: rect)
                        NSColor.black.set()
                        rect.fill(using: .sourceAtop)
                        return true
                    }
                    tinted.draw(in: CGRect(x: size.width - clockSize.width - 44, y: bar.midY - 8, width: 16, height: 16))
                }
            }
        }

        /// ウインドウの中身の見本
        enum WindowContent {
            /// ブラウザのページ（アドレスの欄と、見出し・文の行）
            case page
            /// ファイルの並び（Finder のような）
            case files
        }

        /// 架空のアプリのウインドウ（影・白い地・3 つの丸と題の入った上のバー・中身の見本）
        func appWindow(_ rect: CGRect, title: String, alpha: CGFloat = 1, content: WindowContent) {
            let path = CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil)
            context.saveGState()
            context.setAlpha(alpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -6), blur: 20, color: color(0x000000, 0.2))
            context.addPath(path)
            context.setFillColor(color(0xFFFFFF))
            context.fillPath()
            context.restoreGState()
            context.saveGState()
            context.addPath(path)
            context.clip()
            let bar = CGRect(x: rect.minX, y: rect.maxY - Self.titleBarHeight, width: rect.width, height: Self.titleBarHeight)
            context.setFillColor(color(0xF2F3F5))
            context.fill(bar)
            let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - Self.titleBarHeight)
            switch content {
            case .page: page(in: body)
            case .files: files(in: body)
            }
            context.restoreGState()
            for (index, hex) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
                context.setFillColor(color(hex))
                context.fillEllipse(in: CGRect(x: rect.minX + 12 + CGFloat(index) * 18, y: bar.midY - 6, width: 12, height: 12))
            }
            withAppKit {
                let titleText = text(title, size: 12, weight: .semibold, color: .darkGray)
                let width = min(titleText.size().width, rect.width - 130)
                titleText.draw(with: CGRect(x: rect.midX - width / 2, y: bar.midY - titleText.size().height / 2 + 3, width: width, height: titleText.size().height),
                               options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            }
            context.endTransparencyLayer()
            context.restoreGState()
        }

        /// 灰色の角丸の棒（文字の行の代わり）
        private func bar(_ rect: CGRect, _ hex: UInt32 = 0xE3E6EB) {
            context.setFillColor(color(hex))
            context.addPath(CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
            context.fillPath()
        }

        /// ブラウザのページの見本
        private func page(in body: CGRect) {
            // アドレスの欄
            let toolbar = CGRect(x: body.minX, y: body.maxY - 34, width: body.width, height: 34)
            context.setFillColor(color(0xF7F8FA))
            context.fill(toolbar)
            let field = toolbar.insetBy(dx: max(16, body.width * 0.18), dy: 7)
            context.setFillColor(color(0xE9EBEF))
            context.addPath(CGPath(roundedRect: field, cornerWidth: 7, cornerHeight: 7, transform: nil))
            context.fillPath()
            withAppKit {
                let address = text("github.com/yzanbo/pinstage", size: 11, color: .gray)
                address.draw(at: CGPoint(x: field.midX - address.size().width / 2, y: field.midY - address.size().height / 2))
            }
            // 見出しと文の行
            let left = body.minX + 24
            let width = body.width - 48
            var y = toolbar.minY - 40
            bar(CGRect(x: left, y: y, width: width * 0.55, height: 16), 0xC9D3E0)
            y -= 30
            for (index, ratio) in [0.95, 0.88, 0.92, 0.6, 0.0, 0.9, 0.94, 0.85, 0.7, 0.0, 0.92, 0.8].enumerated() where y > body.minY + 16 {
                if ratio > 0 { bar(CGRect(x: left, y: y, width: width * ratio, height: 7)) }
                y -= index % 5 == 4 ? 14 : 16
            }
        }

        /// ファイルの並びの見本（アイコンは種類で決まる）
        private func files(in body: CGRect) {
            let items: [(String, UTType)] = [
                ("資料", .folder), ("企画書.pdf", .pdf), ("ロゴ.png", .png),
                ("議事録.txt", .plainText), ("写真", .folder), ("見積もり.zip", .zip),
            ]
            let columns = max(2, Int((body.width - 24) / 96))
            let cell = CGSize(width: (body.width - 24) / CGFloat(columns), height: 88)
            withAppKit {
                for (index, (name, type)) in items.enumerated() {
                    let column = index % columns
                    let row = index / columns
                    let origin = CGPoint(x: body.minX + 12 + CGFloat(column) * cell.width, y: body.maxY - 16 - CGFloat(row + 1) * cell.height)
                    guard origin.y > body.minY else { continue }
                    NSWorkspace.shared.icon(for: type).draw(in: CGRect(x: origin.x + cell.width / 2 - 24, y: origin.y + 30, width: 48, height: 48))
                    let label = text(name, size: 11)
                    label.draw(at: CGPoint(x: origin.x + cell.width / 2 - label.size().width / 2, y: origin.y + 10))
                }
            }
        }

        /// 写した画面（ウインドウバー・ウインドウスイッチャー）を、影を付けて置く
        func panel(_ image: CGImage, in frame: CGRect, cornerRadius: CGFloat) {
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: color(0x000000, 0.22))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.addPath(CGPath(roundedRect: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            context.clip()
            context.draw(image, in: frame)
            context.endTransparencyLayer()
            context.restoreGState()
        }

        /// 矢印のカーソル（先端が point）
        func cursor(at point: CGPoint) {
            let path = CGMutablePath()
            path.move(to: point)
            path.addLine(to: CGPoint(x: point.x, y: point.y - 17))
            path.addLine(to: CGPoint(x: point.x + 4, y: point.y - 13))
            path.addLine(to: CGPoint(x: point.x + 7, y: point.y - 20))
            path.addLine(to: CGPoint(x: point.x + 10, y: point.y - 18.5))
            path.addLine(to: CGPoint(x: point.x + 7, y: point.y - 12))
            path.addLine(to: CGPoint(x: point.x + 12, y: point.y - 12))
            path.closeSubpath()
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -1), blur: 2, color: color(0x000000, 0.35))
            context.addPath(path)
            context.setFillColor(color(0x000000))
            context.setStrokeColor(color(0xFFFFFF))
            context.setLineWidth(1.4)
            context.setLineJoin(.round)
            context.drawPath(using: .fillStroke)
            context.restoreGState()
        }

        /// 押しているキー（カーソルの右下に、キーの形の札で出す）
        func key(_ label: String, near point: CGPoint) {
            let rect = CGRect(x: point.x + 14, y: point.y - 42, width: 26, height: 24)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: color(0x000000, 0.25))
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil))
            context.setFillColor(color(0xFFFFFF))
            context.fillPath()
            context.restoreGState()
            withAppKit {
                let symbol = text(label, size: 14, weight: .semibold)
                symbol.draw(at: CGPoint(x: rect.midX - symbol.size().width / 2, y: rect.midY - symbol.size().height / 2))
            }
        }
    }

    // MARK: - 書き出す

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }

    /// 画像を縦横 1/factor にする（2 倍で描いたものを、軽い 1 倍にする）
    private static func downscale(_ image: CGImage, by factor: Int) -> CGImage {
        let width = image.width / factor
        let height = image.height / factor
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private static func writeGIF(_ frames: [GIFFrame], to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in frames {
            CGImageDestinationAddImage(destination, frame.image, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: frame.delay,
                    kCGImagePropertyGIFUnclampedDelayTime: frame.delay,
                ],
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
#endif
