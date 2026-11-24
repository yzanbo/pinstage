import Foundation
import CoreGraphics
import Testing
@testable import PinstageCore

@Suite("並べ方の計算")
struct StageLayoutTests {
    let area = CGRect(x: 100, y: 0, width: 1200, height: 800)

    @Test("均等: 2 枚は左右に半分ずつ")
    func autoTwo() {
        let frames = StageLayout.frames(count: 2, in: area, kind: .auto)
        #expect(frames == [
            CGRect(x: 100, y: 0, width: 600, height: 800),
            CGRect(x: 700, y: 0, width: 600, height: 800),
        ])
    }

    @Test("均等: 4 枚は 2×2 の格子")
    func autoFour() {
        let frames = StageLayout.frames(count: 4, in: area, kind: .auto)
        #expect(frames.count == 4)
        #expect(frames[0] == CGRect(x: 100, y: 0, width: 600, height: 400))
        #expect(frames[3] == CGRect(x: 700, y: 400, width: 600, height: 400))
    }

    @Test("均等: 5 枚は、最後の行の枠を広げて余りを作らない")
    func autoFive() {
        let frames = StageLayout.frames(count: 5, in: area, kind: .auto)
        // 3 列 × 2 行。2 行目は 2 枚なので半分ずつ
        #expect(frames[3] == CGRect(x: 100, y: 400, width: 600, height: 400))
        #expect(frames[4] == CGRect(x: 700, y: 400, width: 600, height: 400))
    }

    @Test("左を大きく: 1 枚目が左に 6 割、残りは右に縦に積む")
    func mainLeft() {
        let frames = StageLayout.frames(count: 3, in: area, kind: .mainLeft)
        #expect(frames[0] == CGRect(x: 100, y: 0, width: 720, height: 800))
        #expect(frames[1] == CGRect(x: 820, y: 0, width: 480, height: 400))
        #expect(frames[2] == CGRect(x: 820, y: 400, width: 480, height: 400))
    }

    @Test("上下に並べる")
    func rows() {
        let frames = StageLayout.frames(count: 2, in: area, kind: .rows)
        #expect(frames == [
            CGRect(x: 100, y: 0, width: 1200, height: 400),
            CGRect(x: 100, y: 400, width: 1200, height: 400),
        ])
    }

    @Test("決めた枠のとおりか（2pt までのずれは気にしない）")
    func placed() {
        let target = CGRect(x: 100, y: 0, width: 600, height: 400)
        #expect(StageLayout.isPlaced(target, at: target))
        #expect(StageLayout.isPlaced(CGRect(x: 101, y: 0, width: 598, height: 401), at: target))
        // アプリが小さくできず、となりへはみ出した
        #expect(!StageLayout.isPlaced(CGRect(x: 100, y: 0, width: 680, height: 400), at: target))
        // 遅れて元の位置に戻った
        #expect(!StageLayout.isPlaced(CGRect(x: 300, y: 50, width: 600, height: 400), at: target))
    }

    @Test("左右に並べる")
    func columns() {
        let frames = StageLayout.frames(count: 2, in: area, kind: .columns)
        #expect(frames == [
            CGRect(x: 100, y: 0, width: 600, height: 800),
            CGRect(x: 700, y: 0, width: 600, height: 800),
        ])
    }

    @Test("4 分割・6 分割: 決まった数の枠。少ないときは残りを空け、多いときは最後の枠に重ねる")
    func fixedGrids() {
        let quarters = StageLayout.frames(count: 3, in: area, kind: .quarters)
        #expect(quarters == [
            CGRect(x: 100, y: 0, width: 600, height: 400),
            CGRect(x: 700, y: 0, width: 600, height: 400),
            CGRect(x: 100, y: 400, width: 600, height: 400),
        ])
        // 6 枚を 4 分割に並べると、5・6 枚目は 4 つ目の枠に重なる
        let overflow = StageLayout.frames(count: 6, in: area, kind: .quarters)
        #expect(overflow[4] == overflow[3] && overflow[5] == overflow[3])
        let sixths = StageLayout.frames(count: 6, in: area, kind: .sixths)
        #expect(sixths[0] == CGRect(x: 100, y: 0, width: 400, height: 400))
        #expect(sixths[2] == CGRect(x: 900, y: 0, width: 400, height: 400))
        #expect(sixths[5] == CGRect(x: 900, y: 400, width: 400, height: 400))
        // 2 枚でも、6 分割の枠の大きさのまま
        #expect(StageLayout.frames(count: 2, in: area, kind: .sixths)[1] == CGRect(x: 500, y: 0, width: 400, height: 400))
    }

    @Test("なくした型（重ねる）と知らない値は、「自動」として読む")
    func legacyKinds() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(LayoutKind.self, from: Data("\"cascade\"".utf8)) == .auto)
        #expect(try decoder.decode(LayoutKind.self, from: Data("\"unknown\"".utf8)) == .auto)
        #expect(try decoder.decode(LayoutKind.self, from: Data("\"sixths\"".utf8)) == .sixths)
        // グループの中に書かれていても、グループごと読める
        let group = try JSONEncoder().encode(LayoutChoice.builtIn(.rows))
        let legacy = Data(String(decoding: group, as: UTF8.self).replacingOccurrences(of: "rows", with: "cascade").utf8)
        #expect(try decoder.decode(LayoutChoice.self, from: legacy) == .builtIn(.auto))
    }

    @Test("重ねて置く（登録した型の枠より多いウインドウ）: 同じ大きさで少しずつずれ、範囲からはみ出さない")
    func cascade() {
        let frames = StageLayout.cascade(count: 3, in: area)
        #expect(frames.count == 3)
        #expect(frames.allSatisfy { $0.size == frames[0].size })
        #expect(frames[1].minX > frames[0].minX)
        #expect(frames[1].minY > frames[0].minY)
        #expect(frames.allSatisfy { area.contains($0) })
    }

    @Test("0 枚なら何も返さない")
    func empty() {
        #expect(StageLayout.frames(count: 0, in: area, kind: .auto).isEmpty)
    }

    @Test("1 枚だけ出すとき、はみ出したところだけ中へ入れる")
    func fit() {
        let frame = CGRect(x: 0, y: 100, width: 500, height: 300)
        #expect(StageLayout.fit(frame, into: area) == CGRect(x: 100, y: 100, width: 500, height: 300))
        let big = CGRect(x: 0, y: 0, width: 2000, height: 300)
        #expect(StageLayout.fit(big, into: area) == CGRect(x: 100, y: 0, width: 1200, height: 300))
    }
}

@Suite("登録した型")
struct CustomLayoutTests {
    let area = CGRect(x: 0, y: 0, width: 1000, height: 500)

    @Test("割合で覚え、別の大きさの範囲にも同じ形で当てはめる")
    func unitRect() {
        let unit = UnitRect(frame: CGRect(x: 100, y: 50, width: 400, height: 250), in: area)
        #expect(unit == UnitRect(x: 0.1, y: 0.1, width: 0.4, height: 0.5))
        let other = CGRect(x: 0, y: 0, width: 2000, height: 1000)
        #expect(unit.rect(in: other) == CGRect(x: 200, y: 100, width: 800, height: 500))
    }

    @Test("範囲からはみ出したところは切る")
    func clipped() {
        let unit = UnitRect(frame: CGRect(x: -100, y: 0, width: 600, height: 500), in: area)
        #expect(unit == UnitRect(x: 0, y: 0, width: 0.5, height: 1))
    }

    @Test("型の枠より多いウインドウも、すべて置く")
    func overflow() {
        let layout = CustomLayout(name: "テスト", slots: [UnitRect(x: 0, y: 0, width: 0.5, height: 1)])
        let frames = layout.frames(count: 3, in: area)
        #expect(frames.count == 3)
        #expect(frames[0] == CGRect(x: 0, y: 0, width: 500, height: 500))
    }
}

@Suite("1 枚だけ出すときの大きさ")
struct SingleWindowSizeTests {
    let area = CGRect(x: 100, y: 0, width: 1200, height: 800)
    let current = CGRect(x: 300, y: 200, width: 500, height: 300)

    @Test("そのまま: 大きさを変えない")
    func keep() {
        #expect(StageLayout.singleFrame(current: current, in: area, size: .keep) == current)
    }

    @Test("縦いっぱい: 横の位置と幅はそのまま、縦はステージいっぱい")
    func fullHeight() {
        #expect(StageLayout.singleFrame(current: current, in: area, size: .fullHeight) == CGRect(x: 300, y: 0, width: 500, height: 800))
        // ストリップと重なっていれば、中へ入れる
        let left = CGRect(x: 0, y: 100, width: 500, height: 300)
        #expect(StageLayout.singleFrame(current: left, in: area, size: .fullHeight) == CGRect(x: 100, y: 0, width: 500, height: 800))
    }

    @Test("ステージいっぱい")
    func fill() {
        #expect(StageLayout.singleFrame(current: current, in: area, size: .fill) == area)
    }

    @Test("初期設定は縦いっぱい。保存して読み戻せる")
    func persistence() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(SingleWindowSize(defaults: defaults) == .fullHeight)
        SingleWindowSize.fill.save(to: defaults)
        #expect(SingleWindowSize(defaults: defaults) == .fill)
    }
}

@Suite("ウインドウをストリップに重ねない")
struct StripAvoidanceTests {
    // ストリップが左の 246pt を使い、ステージはその右側
    let stage = CGRect(x: 246, y: 25, width: 1354, height: 950)

    @Test("画面いっぱいに広がったウインドウは、ステージいっぱいにする")
    func zoomed() {
        let zoomed = CGRect(x: 0, y: 25, width: 1600, height: 950)
        #expect(StripAvoidance.adjusted(zoomed, stage: stage, edge: .left) == stage)
    }

    @Test("重なっているだけのウインドウは、大きさを変えずに右へずらす")
    func overlapping() {
        let window = CGRect(x: 100, y: 200, width: 600, height: 400)
        #expect(StripAvoidance.adjusted(window, stage: stage, edge: .left) == CGRect(x: 246, y: 200, width: 600, height: 400))
    }

    @Test("重なっていない・少しだけのはみ出しなら、そのまま")
    func untouched() {
        #expect(StripAvoidance.adjusted(CGRect(x: 300, y: 100, width: 500, height: 400), stage: stage, edge: .left) == nil)
        #expect(StripAvoidance.adjusted(CGRect(x: 245, y: 100, width: 500, height: 400), stage: stage, edge: .left) == nil)
    }

    @Test("初期設定はオン。保存して読み戻せる")
    func setting() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = StripSettings(defaults: defaults)
        #expect(settings.keepsWindowsOffStrip)
        settings.keepsWindowsOffStrip = false
        settings.save(to: defaults)
        #expect(!StripSettings(defaults: defaults).keepsWindowsOffStrip)
    }
}

@Suite("ダブルクリックで広げる・元に戻す")
struct ZoomMemoryTests {
    let stage = CGRect(x: 246, y: 25, width: 1354, height: 950)
    let full = CGRect(x: 0, y: 25, width: 1600, height: 950)
    let user = CGRect(x: 400, y: 200, width: 700, height: 500)

    @Test("広げたらステージいっぱいに収め、もう一度広げたら元の大きさに戻す")
    func toggle() {
        // 1 回目のダブルクリック: 画面いっぱいに広がる → ステージいっぱいに収める
        let first = StripAvoidance.resolve(current: full, previous: user, memory: .init(), stage: stage, edge: .left)
        #expect(first.target == stage)
        #expect(first.memory.restore == user)
        // 収めたあとは、動かさない
        let settled = StripAvoidance.resolve(current: stage, previous: stage, memory: first.memory, stage: stage, edge: .left)
        #expect(settled.target == nil)
        #expect(settled.memory == first.memory)
        // 2 回目のダブルクリック: また画面いっぱいに広がる → 元の大きさに戻す
        let second = StripAvoidance.resolve(current: full, previous: stage, memory: settled.memory, stage: stage, edge: .left)
        #expect(second.target == user)
        #expect(second.memory == .init())
    }

    @Test("利用者が動かしたら、覚え書きを消す")
    func userMoved() {
        let memory = StripAvoidance.ZoomMemory(restore: user, adjusted: stage)
        let moved = StripAvoidance.resolve(current: CGRect(x: 500, y: 100, width: 600, height: 400), previous: stage, memory: memory, stage: stage, edge: .left)
        #expect(moved.target == nil)
        #expect(moved.memory == .init())
    }

    @Test("ストリップを狭めたら、ストリップの横にくっつけていたウインドウを、新しい幅まで広げる（右端はそのまま）")
    func followNarrowedStrip() {
        // ステージの左端が 246 → 176 に動いた
        let narrowed = CGRect(x: 176, y: 25, width: 1424, height: 950)
        let attached = CGRect(x: 246, y: 25, width: 800, height: 600)
        #expect(StripAvoidance.following(attached, stageFrom: stage, to: narrowed) == CGRect(x: 176, y: 25, width: 870, height: 600))
        // 少しのずれ（2pt まで）は、くっついているとみなす
        #expect(StripAvoidance.following(attached.offsetBy(dx: 2, dy: 0), stageFrom: stage, to: narrowed)?.minX == 176)
        // 離れたところにあるウインドウは動かさない
        #expect(StripAvoidance.following(CGRect(x: 400, y: 25, width: 800, height: 600), stageFrom: stage, to: narrowed) == nil)
        // 広げたとき（左端が右へ動いた）は、ここでは動かさない（重なった分は、収める処理が右へ押し出す）
        #expect(StripAvoidance.following(CGRect(x: 176, y: 25, width: 800, height: 600), stageFrom: narrowed, to: stage) == nil)
    }

    @Test("ほかの辺のストリップを狭めたときも、その辺にくっつけていたウインドウを広げる")
    func followOnOtherEdges() {
        let full = CGRect(x: 0, y: 25, width: 1600, height: 950)
        // 右のストリップをたたんだ（ステージの右端が 1354 → 1532）
        let rightOld = CGRect(x: 0, y: 25, width: 1354, height: 950)
        let rightNew = CGRect(x: 0, y: 25, width: 1532, height: 950)
        #expect(StripAvoidance.following(rightOld, stageFrom: rightOld, to: rightNew) == rightNew)
        // 下のストリップをたたんだ（アクセシビリティの座標では、下の辺は maxY）
        let bottomOld = CGRect(x: 0, y: 25, width: 1600, height: 886)
        let bottomNew = CGRect(x: 0, y: 25, width: 1600, height: 904)
        #expect(StripAvoidance.following(CGRect(x: 100, y: 400, width: 500, height: 511), stageFrom: bottomOld, to: bottomNew) == CGRect(x: 100, y: 400, width: 500, height: 529))
        // ストリップを左から右へ移した: 前のステージいっぱいのウインドウは、左へ広がる（右にはみ出した分は、収める処理が直す）
        #expect(StripAvoidance.following(stage, stageFrom: stage, to: rightOld) == full)
    }

    @Test("右・上・下のストリップに重なったウインドウも、ステージのほうへずらす")
    func otherEdges() {
        // 右のストリップ（ステージは左側）
        let left = CGRect(x: 0, y: 25, width: 1354, height: 950)
        #expect(StripAvoidance.adjusted(CGRect(x: 900, y: 200, width: 600, height: 400), stage: left, edge: .right) == CGRect(x: 754, y: 200, width: 600, height: 400))
        #expect(StripAvoidance.adjusted(CGRect(x: 700, y: 200, width: 600, height: 400), stage: left, edge: .right) == nil)
        // 上のストリップ（アクセシビリティの座標では、上の辺は minY。ステージは下側）
        let lower = CGRect(x: 0, y: 89, width: 1600, height: 886)
        #expect(StripAvoidance.adjusted(CGRect(x: 100, y: 40, width: 600, height: 400), stage: lower, edge: .top) == CGRect(x: 100, y: 89, width: 600, height: 400))
        // 下のストリップ（ステージは上側）
        let upper = CGRect(x: 0, y: 25, width: 1600, height: 886)
        #expect(StripAvoidance.adjusted(CGRect(x: 100, y: 600, width: 600, height: 400), stage: upper, edge: .bottom) == CGRect(x: 100, y: 511, width: 600, height: 400))
        // ストリップのない側へのはみ出しは、気にしない
        #expect(StripAvoidance.adjusted(CGRect(x: -100, y: 100, width: 600, height: 400), stage: upper, edge: .bottom) == nil)
    }

    @Test("上下のストリップでは、縦いっぱいに広げたかで、広げる・元に戻すを決める")
    func zoomWithBar() {
        let upper = CGRect(x: 0, y: 25, width: 1600, height: 886)
        let zoomed = CGRect(x: 0, y: 25, width: 1600, height: 950)
        let first = StripAvoidance.resolve(current: zoomed, previous: user, memory: .init(), stage: upper, edge: .bottom)
        #expect(first.target == upper)
        #expect(first.memory.restore == user)
        let second = StripAvoidance.resolve(current: zoomed, previous: upper, memory: first.memory, stage: upper, edge: .bottom)
        #expect(second.target == user)
    }

    @Test("重なっただけ（広げていない）なら、右へずらすだけで覚えない")
    func overlapOnly() {
        let window = CGRect(x: 100, y: 200, width: 600, height: 400)
        let result = StripAvoidance.resolve(current: window, previous: nil, memory: .init(), stage: stage, edge: .left)
        #expect(result.target == CGRect(x: 246, y: 200, width: 600, height: 400))
        #expect(result.memory.restore == nil)
    }
}

@Suite("ストリップに並べる、ふつうのウインドウ")
struct WindowEligibilityTests {
    @Test("種類が「ふつうのウインドウ」なら並べ、パネル・ダイアログは並べない")
    func subrole() {
        #expect(WindowEligibility.verdict(subrole: "AXStandardWindow") == .accept)
        #expect(WindowEligibility.verdict(subrole: "AXDialog") == .reject)
        #expect(WindowEligibility.verdict(subrole: "AXFloatingWindow") == .reject)
        #expect(WindowEligibility.verdict(subrole: "AXSystemDialog") == .reject)
    }

    @Test("枠を自前で描くウインドウ（種類が「不明」・種類なし）は、高さと大きさで決める")
    func frameless() {
        #expect(WindowEligibility.verdict(subrole: "AXUnknown") == .needsGeometry)
        #expect(WindowEligibility.verdict(subrole: nil) == .needsGeometry)
        #expect(WindowEligibility.isNormalWindow(layer: 0, size: CGSize(width: 1200, height: 800)))
        // ほかのウインドウの上に浮くパネル
        #expect(!WindowEligibility.isNormalWindow(layer: 3, size: CGSize(width: 1200, height: 800)))
        // ツールチップ・タブのバーなどの小さな部品
        #expect(!WindowEligibility.isNormalWindow(layer: 0, size: CGSize(width: 1800, height: 39)))
        #expect(!WindowEligibility.hasWindowSize(CGSize(width: 64, height: 64)))
        #expect(WindowEligibility.hasWindowSize(CGSize(width: 100, height: 100)))
    }
}
