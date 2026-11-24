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

    @Test("重ねる: 同じ大きさで少しずつずれ、範囲からはみ出さない")
    func cascade() {
        let frames = StageLayout.frames(count: 3, in: area, kind: .cascade)
        #expect(frames.count == 3)
        #expect(frames.allSatisfy { $0.size == frames[0].size })
        #expect(frames[1].minX > frames[0].minX)
        #expect(frames[1].minY > frames[0].minY)
        #expect(frames.allSatisfy { area.contains($0) })
    }

    @Test("間を空けると、ウインドウ同士の間も端との間も同じになる")
    func gap() {
        let frames = StageLayout.frames(count: 2, in: area, kind: .auto, gap: 20)
        #expect(frames[0].minX == area.minX + 20)
        #expect(frames[1].minX - frames[0].maxX == 20)
        #expect(area.maxX - frames[1].maxX == 20)
        #expect(frames[0].minY == 20)
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
        #expect(StripAvoidance.adjusted(zoomed, stage: stage) == stage)
    }

    @Test("重なっているだけのウインドウは、大きさを変えずに右へずらす")
    func overlapping() {
        let window = CGRect(x: 100, y: 200, width: 600, height: 400)
        #expect(StripAvoidance.adjusted(window, stage: stage) == CGRect(x: 246, y: 200, width: 600, height: 400))
    }

    @Test("重なっていない・少しだけのはみ出しなら、そのまま")
    func untouched() {
        #expect(StripAvoidance.adjusted(CGRect(x: 300, y: 100, width: 500, height: 400), stage: stage) == nil)
        #expect(StripAvoidance.adjusted(CGRect(x: 245, y: 100, width: 500, height: 400), stage: stage) == nil)
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
        let first = StripAvoidance.resolve(current: full, previous: user, memory: .init(), stage: stage)
        #expect(first.target == stage)
        #expect(first.memory.restore == user)
        // 収めたあとは、動かさない
        let settled = StripAvoidance.resolve(current: stage, previous: stage, memory: first.memory, stage: stage)
        #expect(settled.target == nil)
        #expect(settled.memory == first.memory)
        // 2 回目のダブルクリック: また画面いっぱいに広がる → 元の大きさに戻す
        let second = StripAvoidance.resolve(current: full, previous: stage, memory: settled.memory, stage: stage)
        #expect(second.target == user)
        #expect(second.memory == .init())
    }

    @Test("利用者が動かしたら、覚え書きを消す")
    func userMoved() {
        let memory = StripAvoidance.ZoomMemory(restore: user, adjusted: stage)
        let moved = StripAvoidance.resolve(current: CGRect(x: 500, y: 100, width: 600, height: 400), previous: stage, memory: memory, stage: stage)
        #expect(moved.target == nil)
        #expect(moved.memory == .init())
    }

    @Test("重なっただけ（広げていない）なら、右へずらすだけで覚えない")
    func overlapOnly() {
        let window = CGRect(x: 100, y: 200, width: 600, height: 400)
        let result = StripAvoidance.resolve(current: window, previous: nil, memory: .init(), stage: stage)
        #expect(result.target == CGRect(x: 246, y: 200, width: 600, height: 400))
        #expect(result.memory.restore == nil)
    }
}
