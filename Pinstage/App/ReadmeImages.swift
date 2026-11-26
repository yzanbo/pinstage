#if DEBUG
import AppKit
import Carbon.HIToolbox
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
/// - groups.gif: ＋ からステージをグループとして保存 → グループの行で呼び出す → ⌃⌥3 で保存したグループに戻す
/// - switcher.gif: ⌥Tab でウインドウスイッチャーを開く → Tab とスペースで 2 つ選ぶ → ↩ でステージに並べる
enum ReadmeImages {
    /// 2 倍の画素で描く（PNG はそのまま、GIF は 1 倍にして軽くする）
    private static let scale: CGFloat = 2
    /// 画像の大きさ（README に並べるので、どれも同じにする。ウインドウスイッチャーが収まる幅と、グループが 3 つ並んでもウインドウの一覧が隠れない高さ）
    private static let imageSize = CGSize(width: 980, height: 700)

    static func render(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        StripPreview.withSample(scenario: .desktopList) { sample in
            sample.stage.stripSettings.itemSize = .list
            sample.stage.stripSettings.mode = .alwaysShown
            sample.stage.stripSettings.edge = .left
            let scene = Scene(sample: sample)
            write("hero.png", folder) { try writePNG(scene.hero(), to: $0) }
            write("arrange.gif", folder) { try writeGIF(scene.arrange(), to: $0) }
            write("switcher.gif", folder) { try writeGIF(scene.switcher(), to: $0) }
            // グループを足すので、最後に作る
            write("groups.gif", folder) { try writeGIF(scene.groups(), to: $0) }
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
        func frames(for count: Int, layout: LayoutChoice = .builtIn(.auto)) -> [CGRect] {
            // 並べ方は上が原点の座標（アクセシビリティの座標）で計算するので、ステージの真ん中で上下を折り返して渡し、戻す
            let flip = { ScreenCoordinates.toAccessibility($0, primaryScreenHeight: stage.maxY + stage.minY) }
            let area = flip(stage)
            let frames = count == 1
                ? [StageLayout.singleFrame(current: area.insetBy(dx: area.width * 0.18, dy: area.height * 0.12), in: area, size: .default)]
                : layout.frames(count: count, in: area, customLayouts: [])
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
        var mail: WindowItem { sample.windows[1] }
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
            // ウインドウバーのパネルの中身を外す（出さないパネルの、仮の大きさの並びが、行の枠の記録に混ざらないように）
            strip.close()
            // このデスクトップのウインドウを並べる
            strip.spaceState.windowIDs = Set(sample.windows.filter { stage.windowSpaces?[$0.id]?.contains(Self.desktop) ?? true }.map(\.id))
            let size = desk.strip.size
            let view = StripView(stage: stage, thumbnails: ThumbnailStore(), shortcuts: ShortcutCenter(), strip: strip, actions: AppActions())
                .frame(width: size.width, height: size.height)
            let image = try capture(view, size: size)
            // 行の枠（一覧の座標）を、ウインドウバーの中身の座標（左上が原点）にする。カーソルを行に置くのに使う
            let reorder = strip.windowReorder
            let rows = reorder.frames.mapValues { $0.offsetBy(dx: reorder.listFrame.minX, dy: reorder.listFrame.minY) }
            return StripShot(image: image, frame: desk.strip, rows: rows, groups: strip.groupTargets.frames)
        }

        /// ステージに並べた items（アプリと同じ並べ方）
        func placed(_ items: [WindowItem], on desk: Desk, layout: LayoutChoice = .builtIn(.auto)) -> [Placed] {
            zip(items, desk.frames(for: items.count, layout: layout)).map { ($0, $1, 1) }
        }

        /// ステージの並びが before から after へ変わる途中（t: 0〜1）。両方にあるウインドウは動き、なくなるものは消え、増えるものは広がって現れる
        func transition(from before: [Placed], to after: [Placed], _ t: CGFloat) -> [Placed] {
            let leaving = before.filter { old in !after.contains { $0.item.id == old.item.id } }.map { ($0.item, $0.frame, 1 - t) }
            let arriving = after.map { new in
                before.first { $0.item.id == new.item.id }.map { (new.item, lerp($0.frame, new.frame, t), CGFloat(1)) }
                    ?? (new.item, grow(new.frame, from: 0.92, t), t)
            }
            return leaving + arriving
        }

        /// デスクトップ・ステージのウインドウ・ウインドウバーを描く（メニューバーとカーソルは、その上に描く）
        func paint(_ canvas: Canvas, strip: StripShot, windows: [Placed]) {
            canvas.wallpaper()
            for window in windows {
                canvas.appWindow(window.frame, title: window.item.title, alpha: window.alpha, content: .init(window.item))
            }
            canvas.panel(strip.image, in: strip.frame, cornerRadius: 16)
        }

        // MARK: hero.png

        func hero() throws -> CGImage {
            let canvas = Canvas(size: ReadmeImages.imageSize, scale: ReadmeImages.scale)
            let desk = desk(canvas.size)
            let shot = try strip(selection: [safari, finder], on: desk)
            paint(canvas, strip: shot, windows: placed([safari, finder], on: desk))
            canvas.cursor(at: shot.center(ofRow: 2).applying(.init(translationX: 40, y: -4)))
            canvas.menuBar()
            return canvas.image()
        }

        // MARK: arrange.gif

        func arrange() throws -> [GIFFrame] {
            let desk = desk(ReadmeImages.imageSize)
            let none = try strip(selection: [], on: desk)
            let one = try strip(selection: [safari], on: desk)
            let two = try strip(selection: [safari, finder], on: desk)
            let single = placed([safari], on: desk)
            let pair = placed([safari, finder], on: desk)
            let safariRow = none.center(ofRow: 0)
            let finderRow = none.center(ofRow: 2)
            var film = Film(scene: self, size: desk.size)

            // 1. 何も出していないところから、Safari の行へ
            let start = CGPoint(x: desk.stage.midX, y: desk.stage.midY - 40)
            film.add(none, windows: [], cursor: start, delay: 0.8)
            for t in steps(10) { film.add(none, windows: [], cursor: lerp(start, safariRow, t), delay: 0.04) }
            film.add(none, windows: [], cursor: safariRow, delay: 0.3)
            // 2. クリックすると、Safari だけがステージに出る
            for t in steps(5) { film.add(one, windows: transition(from: [], to: single, t), cursor: safariRow, delay: 0.04) }
            film.add(one, windows: single, cursor: safariRow, delay: 1.0)
            // 3. ⌘ を押しながら Finder の行へ
            for t in steps(8) { film.add(one, windows: single, cursor: lerp(safariRow, finderRow, t), key: "⌘", delay: 0.04) }
            film.add(one, windows: single, cursor: finderRow, key: "⌘", delay: 0.4)
            // 4. ⌘＋クリックすると、Finder を横に足して、2 つを並べる
            for t in steps(6) { film.add(two, windows: transition(from: single, to: pair, t), cursor: finderRow, key: "⌘", delay: 0.04) }
            film.add(two, windows: pair, cursor: finderRow, delay: 2.0)
            return film.frames
        }

        // MARK: groups.gif

        func groups() throws -> [GIFFrame] {
            let desk = desk(ReadmeImages.imageSize)
            let pair = [safari, finder]
            let develop = sample.groups[0]
            let before = try strip(selection: pair, on: desk)
            // ＋ から保存したグループ（本物には保存しない）
            var saved: StageGroup?
            sample.stage.editPreviewLibrary { library in
                let content = StageGroup.Content(members: pair.compactMap(\.signature), layout: .builtIn(.auto), displayID: nil)
                saved = library.addGroup(name: nil, content: content)
            }
            guard let saved else { throw CocoaError(.fileWriteUnknown) }
            let afterSave = try strip(selection: pair, on: desk)
            let recalled = try strip(selection: [safari, mail], on: desk)
            let back = try strip(selection: pair, on: desk)
            let pairWindows = placed(pair, on: desk)
            let developWindows = placed([safari, mail], on: desk, layout: develop.layout)
            // グループの見出しの ＋ と、そこから開くメニュー（highlighted: 選んでいる項目）
            let plus = before.groupHeaderButton(above: develop.id)
            let menuOrigin = CGPoint(x: plus.x - 10, y: plus.y - 14)
            let saveItem = Canvas.menuItemCenter(0, origin: menuOrigin)
            func menu(highlighted: Int?) -> (Canvas) -> Void {
                { $0.menu(["ステージをグループとして保存", "見えている画面を記録"], highlighted: highlighted, origin: menuOrigin) }
            }
            let developRow = afterSave.center(ofGroup: develop.id)
            let shortcut = "⌃⌥\(sample.stage.library.groups.firstIndex { $0.id == saved.id }.map { $0 + 1 } ?? 3)"
            var film = Film(scene: self, size: desk.size)

            // 1. Safari と Finder を並べたところから、グループの見出しの ＋ へ
            let start = CGPoint(x: desk.stage.midX - 60, y: desk.stage.midY)
            film.add(before, windows: pairWindows, cursor: start, delay: 0.8)
            for t in steps(10) { film.add(before, windows: pairWindows, cursor: lerp(start, plus, t), delay: 0.04) }
            // 2. ＋ を押すとメニューが開き、「ステージをグループとして保存」を選ぶ
            film.add(before, windows: pairWindows, cursor: plus, delay: 0.5, above: menu(highlighted: nil))
            for t in steps(5) {
                film.add(before, windows: pairWindows, cursor: lerp(plus, saveItem, t), delay: 0.04, above: menu(highlighted: t == 1 ? 0 : nil))
            }
            film.add(before, windows: pairWindows, cursor: saveItem, delay: 0.5, above: menu(highlighted: 0))
            // 3. グループの行が増える
            film.add(afterSave, windows: pairWindows, cursor: saveItem, delay: 1.2)
            // 4. グループ「開発」の行を押すと、そのグループの組み合わせに切り替わる
            for t in steps(10) { film.add(afterSave, windows: pairWindows, cursor: lerp(saveItem, developRow, t), delay: 0.04) }
            film.add(afterSave, windows: pairWindows, cursor: developRow, delay: 0.3)
            for t in steps(6) { film.add(recalled, windows: transition(from: pairWindows, to: developWindows, t), cursor: developRow, delay: 0.04) }
            film.add(recalled, windows: developWindows, cursor: developRow, delay: 1.2)
            // 5. ⌃⌥3 で、保存したグループ（3 つ目）に戻る
            film.add(recalled, windows: developWindows, cursor: developRow, key: shortcut, delay: 0.5)
            for t in steps(6) {
                film.add(back, windows: transition(from: developWindows, to: pairWindows, t), cursor: developRow, key: shortcut, delay: 0.04)
            }
            film.add(back, windows: pairWindows, cursor: developRow, delay: 2.0)
            return film.frames
        }

        // MARK: switcher.gif

        func switcher() throws -> [GIFFrame] {
            let desk = desk(ReadmeImages.imageSize)
            let pair = [safari, finder]
            let before = try strip(selection: pair, on: desk)
            sample.stage.windowSwitcherSettings.appearance = .icons
            sample.stage.windowSwitcherSettings.displaySize = .small
            // アプリと同じく、ディスプレイの使える範囲に収まるように並べて、真ん中に開く
            let visible = Canvas.visibleFrame(in: desk.size)
            let preview = DesktopPickerController.preview(stage: sample.stage, screen: sample.screen, fitting: visible)
            let pickerFrame = CGRect(x: visible.midX - preview.size.width / 2, y: visible.midY - preview.size.height / 2,
                                     width: preview.size.width, height: preview.size.height)
            /// いまのウインドウスイッチャーを写す（keyCode を渡すと、本物と同じくそのキーを押してから写す）
            func shoot(after keyCode: Int? = nil) throws -> CGImage {
                if let keyCode { press(keyCode, on: preview.model) }
                return try capture(preview.view, size: preview.size)
            }
            /// ウインドウスイッチャーを開いて重ねる（alpha: 濃さ。開く・閉じる途中は薄く、少し小さい）
            func picker(_ image: CGImage, alpha: CGFloat = 1) -> (Canvas) -> Void {
                { $0.panel(image, in: grow(pickerFrame, from: 0.96, alpha), cornerRadius: 18, alpha: alpha) }
            }
            // 選択と印を動かしながら写す（デスクトップ 1: Safari・メール・Finder・ターミナルの順）
            let opened = try shoot()
            let onMail = try shoot(after: kVK_Tab)
            let markedMail = try shoot(after: kVK_Space)
            let onFinder = try shoot(after: kVK_Tab)
            let onTerminal = try shoot(after: kVK_Tab)
            let markedBoth = try shoot(after: kVK_Space)
            // ↩ で、印を付けたウインドウをステージに並べる（本物の confirm と同じ組み合わせ。見本なのでウインドウは動かさない）
            let picked = preview.model.marked.compactMap(sample.stage.item(for:))
            let after = try strip(selection: picked, on: desk)
            let pairWindows = placed(pair, on: desk)
            let pickedWindows = placed(picked, on: desk)
            var film = Film(scene: self, size: desk.size)

            // 1. Safari と Finder を並べたところで ⌥Tab を押すと、ウインドウスイッチャーが開く
            film.add(before, windows: pairWindows, delay: 0.8)
            for t in steps(4) { film.add(before, windows: pairWindows, caption: "⌥ Tab", delay: 0.04, above: picker(opened, alpha: t)) }
            film.add(before, windows: pairWindows, caption: "⌥ Tab", delay: 0.7, above: picker(opened))
            // 2. Tab でメールへ移り、スペースで印を付ける
            film.add(before, windows: pairWindows, caption: "Tab", delay: 0.6, above: picker(onMail))
            film.add(before, windows: pairWindows, caption: "スペース", delay: 0.8, above: picker(markedMail))
            // 3. Tab でターミナルへ移り、スペースで印を付ける
            film.add(before, windows: pairWindows, caption: "Tab", delay: 0.35, above: picker(onFinder))
            film.add(before, windows: pairWindows, caption: "Tab", delay: 0.5, above: picker(onTerminal))
            film.add(before, windows: pairWindows, caption: "スペース", delay: 0.9, above: picker(markedBoth))
            // 4. ↩ を押すと閉じて、印を付けたウインドウがステージに並ぶ（ウインドウスイッチャーは前半で消える）
            for t in steps(6) {
                film.add(after, windows: transition(from: pairWindows, to: pickedWindows, t), caption: "↩", delay: 0.04,
                         above: t <= 0.5 ? picker(markedBoth, alpha: 1 - t * 2) : { _ in })
            }
            film.add(after, windows: pickedWindows, caption: "↩", delay: 0.5)
            film.add(after, windows: pickedWindows, delay: 2.0)
            return film.frames
        }
    }

    /// GIF のコマを描きためる
    private struct Film {
        let scene: Scene
        let size: CGSize
        private(set) var frames: [GIFFrame] = []

        init(scene: Scene, size: CGSize) {
            self.scene = scene
            self.size = size
        }

        /// 1 コマを描く。下から、デスクトップ・ステージのウインドウ・ウインドウバー・above（メニュー・ウインドウスイッチャーなど）・
        /// メニューバー・カーソル（key: カーソルの横に出す、押しているキー）・caption（画面の下に出す、押したキー。キーボードだけで操作する場面）
        mutating func add(_ strip: StripShot, windows: [Placed], cursor: CGPoint? = nil, key: String? = nil, caption: String? = nil,
                          delay: Double, above: (Canvas) -> Void = { _ in }) {
            let canvas = Canvas(size: size, scale: ReadmeImages.scale)
            scene.paint(canvas, strip: strip, windows: windows)
            above(canvas)
            canvas.menuBar()
            if let cursor {
                canvas.cursor(at: cursor)
                if let key { canvas.key(key, near: cursor) }
            }
            if let caption { canvas.keyCaption(caption) }
            frames.append(GIFFrame(image: downscale(canvas.image(), by: Int(ReadmeImages.scale)), delay: delay))
        }
    }

    /// アプリと同じ部品を、明るい見た目・透明な地で描き写す（架空のデスクトップに重ねる）
    private static func capture(_ view: some View, size: CGSize) throws -> CGImage {
        guard let image = StripPreview.snapshot(view, size: size, appearance: .aqua, transparent: true)?.cgImage else {
            throw CocoaError(.fileWriteUnknown)
        }
        return image
    }

    /// ウインドウスイッチャーに、キーを押したことを送る（Tab・スペース）
    private static func press(_ keyCode: Int, on model: DesktopPickerModel) {
        let characters = keyCode == kVK_Tab ? "\t" : " "
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                           characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                                           keyCode: UInt16(keyCode))
        else { return }
        _ = model.handleKey(event)
    }

    /// 動きの進み具合（count コマに分けた 1/count・2/count・…・1）
    private static func steps(_ count: Int) -> [CGFloat] {
        (1...count).map { CGFloat($0) / CGFloat(count) }
    }

    // MARK: - 写したもの

    /// 写したウインドウバー（frame はキャンバスに置く枠。rows はウインドウの行の番号ごと、groups はグループごとの行の枠。
    /// 行の枠は、ウインドウバーの中身の座標で、左上が原点）
    private struct StripShot {
        let image: CGImage
        let frame: CGRect
        let rows: [Int: CGRect]
        let groups: [UUID: CGRect]

        /// ウインドウの行の真ん中（キャンバスの座標）
        func center(ofRow index: Int) -> CGPoint {
            point(rows[index].map { CGPoint(x: $0.midX, y: $0.midY) })
        }

        /// グループの行の真ん中（キャンバスの座標）
        func center(ofGroup id: UUID) -> CGPoint {
            point(groups[id].map { CGPoint(x: $0.midX, y: $0.midY) })
        }

        /// グループの見出しの右の ＋（そのグループの行のすぐ上の行の、右端）
        func groupHeaderButton(above id: UUID) -> CGPoint {
            point(groups[id].map { CGPoint(x: $0.maxX - 14, y: $0.minY - 19) })
        }

        /// ウインドウバーの中身の座標を、キャンバスの座標にする（分からなければ、ウインドウバーの真ん中）
        private func point(_ local: CGPoint?) -> CGPoint {
            guard let local else { return CGPoint(x: frame.midX, y: frame.midY) }
            return CGPoint(x: frame.minX + local.x, y: frame.maxY - local.y)
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

        /// ウインドウの中身の見本（アプリで決める）
        enum WindowContent {
            /// ブラウザのページ（アドレスの欄と、見出し・文の行。Safari）
            case page
            /// ファイルの並び（Finder）
            case files
            /// 黒い地の文字（ターミナル）
            case terminal
            /// 見出しと文の行（ほかのアプリ）
            case document

            init(_ item: WindowItem) {
                self = switch item.bundleID {
                case "com.apple.Safari": .page
                case "com.apple.finder": .files
                case "com.apple.Terminal": .terminal
                default: .document
                }
            }
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
            case .terminal: terminal(in: body)
            case .document: lines(in: body, top: body.maxY - 24)
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
            lines(in: body, top: toolbar.minY - 24)
        }

        /// 見出しと文の行（top は見出しの上の端）
        private func lines(in body: CGRect, top: CGFloat) {
            let left = body.minX + 24
            let width = body.width - 48
            var y = top - 16
            bar(CGRect(x: left, y: y, width: width * 0.55, height: 16), 0xC9D3E0)
            y -= 30
            for (index, ratio) in [0.95, 0.88, 0.92, 0.6, 0.0, 0.9, 0.94, 0.85, 0.7, 0.0, 0.92, 0.8].enumerated() where y > body.minY + 16 {
                if ratio > 0 { bar(CGRect(x: left, y: y, width: width * ratio, height: 7)) }
                y -= index % 5 == 4 ? 14 : 16
            }
        }

        /// ターミナルの見本（黒い地に、打った命令と出力の行）
        private func terminal(in body: CGRect) {
            context.setFillColor(color(0x1E1E1E))
            context.fill(body)
            let output: [(String, NSColor)] = [
                ("% make test", .white), ("Building PinstageCore…", .lightGray), ("✔ Test run passed", NSColor(red: 0.4, green: 0.85, blue: 0.45, alpha: 1)),
                ("% make run", .white), ("Pinstage を起動しました", .lightGray), ("% ", .white),
            ]
            withAppKit {
                var y = body.maxY - 26
                for (line, color) in output where y > body.minY + 8 {
                    NSAttributedString(string: line, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: color])
                        .draw(at: CGPoint(x: body.minX + 14, y: y))
                    y -= 20
                }
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

        /// 写した画面（ウインドウバー・ウインドウスイッチャー）を、影を付けて置く（alpha: 濃さ。開く・閉じる途中は薄い）
        func panel(_ image: CGImage, in frame: CGRect, cornerRadius: CGFloat, alpha: CGFloat = 1) {
            context.saveGState()
            context.setAlpha(alpha)
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

        /// 押したキー（画面の下の真ん中に、大きな札で出す。キーボードだけで操作する場面で使う）
        func keyCaption(_ label: String) {
            let caption = text(label, size: 22, weight: .semibold, color: .white)
            let rect = CGRect(x: size.width / 2 - (caption.size().width + 36) / 2, y: 18, width: caption.size().width + 36, height: 44)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil))
            context.setFillColor(color(0x000000, 0.65))
            context.fillPath()
            withAppKit {
                caption.draw(at: CGPoint(x: rect.midX - caption.size().width / 2, y: rect.midY - caption.size().height / 2))
            }
        }

        /// メニューの項目の高さと、メニューの幅
        static let menuItemHeight: CGFloat = 24
        static let menuWidth: CGFloat = 230

        /// 開いたメニューの、その番号の項目の真ん中（origin はメニューの左上の角）
        static func menuItemCenter(_ index: Int, origin: CGPoint) -> CGPoint {
            CGPoint(x: origin.x + menuWidth / 2, y: origin.y - 6 - menuItemHeight * (CGFloat(index) + 0.5))
        }

        /// 開いたメニュー（items を縦に並べ、highlighted の項目を選んだ色にする。origin は左上の角）
        func menu(_ items: [String], highlighted: Int?, origin: CGPoint) {
            let height = Self.menuItemHeight * CGFloat(items.count) + 12
            let rect = CGRect(x: origin.x, y: origin.y - height, width: Self.menuWidth, height: height)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: color(0x000000, 0.25))
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
            context.setFillColor(color(0xF6F6F7, 0.98))
            context.fillPath()
            context.restoreGState()
            for (index, item) in items.enumerated() {
                let center = Self.menuItemCenter(index, origin: origin)
                let row = CGRect(x: rect.minX + 5, y: center.y - Self.menuItemHeight / 2, width: rect.width - 10, height: Self.menuItemHeight)
                if index == highlighted {
                    context.addPath(CGPath(roundedRect: row, cornerWidth: 5, cornerHeight: 5, transform: nil))
                    context.setFillColor(color(0x0A84FF))
                    context.fillPath()
                }
                withAppKit {
                    let label = text(item, size: 13, color: index == highlighted ? .white : .black)
                    label.draw(at: CGPoint(x: row.minX + 12, y: row.midY - label.size().height / 2))
                }
            }
        }

        /// 押しているキー（カーソルの右下に、キーの形の札で出す）
        func key(_ label: String, near point: CGPoint) {
            let symbol = text(label, size: 14, weight: .semibold)
            let rect = CGRect(x: point.x + 14, y: point.y - 42, width: max(26, symbol.size().width + 14), height: 24)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: color(0x000000, 0.25))
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil))
            context.setFillColor(color(0xFFFFFF))
            context.fillPath()
            context.restoreGState()
            withAppKit {
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
