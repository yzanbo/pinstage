import Foundation
import CoreGraphics
import Testing
@testable import PinstageCore

@Suite("ステージの選び方")
struct StageSelectionTests {
    @Test("クリックで、そのウインドウだけを出す")
    func showOnly() {
        var stage = StageSelection(["a", "b"])
        stage.showOnly("c")
        #expect(stage.members == ["c"])
    }

    @Test("⌘＋クリックで、足して・外す")
    func toggle() {
        var stage = StageSelection(["a"])
        stage.toggle("b")
        #expect(stage.members == ["a", "b"])
        stage.toggle("a")
        #expect(stage.members == ["b"])
    }

    @Test("ドラッグで足すと、出していたものもいちばん前に移る")
    func add() {
        var stage = StageSelection(["a", "b"])
        stage.add("a")
        #expect(stage.members == ["b", "a"])
    }

    @Test("同じウインドウは 2 回入らない")
    func unique() {
        #expect(StageSelection(["a", "a", "b"]).members == ["a", "b"])
    }

    @Test("閉じたウインドウを外す")
    func prune() {
        var stage = StageSelection(["a", "b", "c"])
        stage.prune(keeping: ["a", "c"])
        #expect(stage.members == ["a", "c"])
    }
}

@Suite("ストリップの並び")
struct RecentOrderTests {
    @Test("新しいものは先頭に足し、なくなったものは除く")
    func syncing() {
        #expect(RecentOrder.syncing([1, 2, 3], with: [3, 4, 1]) == [4, 1, 3])
    }
}

@Suite("グループの名前")
struct GroupNamingTests {
    @Test("使っていないいちばん小さい番号")
    func nextName() {
        #expect(GroupNaming.nextName(existing: []) == "グループ 1")
        #expect(GroupNaming.nextName(existing: ["グループ 1", "グループ 3"]) == "グループ 2")
    }

    @Test("空白だけの名前は使わない")
    func normalized() {
        #expect(GroupNaming.normalized("  開発 ") == "開発")
        #expect(GroupNaming.normalized("   ") == nil)
    }
}

@Suite("ドラッグで並べ替え")
struct ListReorderTests {
    let frames: [Int: CGRect] = [
        0: CGRect(x: 0, y: 0, width: 100, height: 40),
        1: CGRect(x: 0, y: 46, width: 100, height: 40),
        2: CGRect(x: 0, y: 92, width: 100, height: 40),
    ]

    @Test("ポインタの高さから、落とす位置を決める（行の真ん中より上なら、その行の前）")
    func dropIndex() {
        #expect(ListReorder.dropIndex(forY: -10, frames: frames, count: 3) == 0)
        #expect(ListReorder.dropIndex(forY: 30, frames: frames, count: 3) == 1)
        #expect(ListReorder.dropIndex(forY: 60, frames: frames, count: 3) == 1)
        #expect(ListReorder.dropIndex(forY: 200, frames: frames, count: 3) == 3)
    }

    @Test("後ろへ移すときも前へ移すときも、落とした位置に入る")
    func moved() {
        #expect(ListReorder.moved(["a", "b", "c", "d"], from: 0, dropIndex: 3) == ["b", "c", "a", "d"])
        #expect(ListReorder.moved(["a", "b", "c", "d"], from: 0, dropIndex: 4) == ["b", "c", "d", "a"])
        #expect(ListReorder.moved(["a", "b", "c", "d"], from: 3, dropIndex: 1) == ["a", "d", "b", "c"])
        #expect(ListReorder.moved(["a", "b"], from: 5, dropIndex: 0) == ["a", "b"])
    }

    @Test("自分の前・すぐ後ろに落としても、並びは変わらない")
    func noOp() {
        #expect(ListReorder.isNoOp(from: 1, dropIndex: 1))
        #expect(ListReorder.isNoOp(from: 1, dropIndex: 2))
        #expect(!ListReorder.isNoOp(from: 1, dropIndex: 3))
        #expect(ListReorder.moved(["a", "b", "c"], from: 1, dropIndex: 2) == ["a", "b", "c"])
    }
}

@Suite("ストリップの行の高さ")
struct StripRowSizingTests {
    @Test("少ないときは、一覧の高さに収まるよう広げる（上限まで）")
    func fill() {
        // (700 - 0 - 6×6) ÷ 7 ≒ 94.9 → 上限 200 の中なので、そのまま
        let height = StripRowSizing.rowHeight(available: 700, count: 7, spacing: 6, footer: 0, maximum: 200)
        #expect(abs(height - (700 - 36) / 7) < 0.001)
        #expect(StripRowSizing.rowHeight(available: 700, count: 2, spacing: 6, footer: 0, maximum: 88) == 88)
    }

    @Test("多いときは小さい値になり、中身の高さのまま（スクロール）になる")
    func overflow() {
        // (300 - 24 - 6×39) ÷ 40 ≒ 1pt。どの行の中身より低いので、中身の高さのまま並ぶ
        #expect(StripRowSizing.rowHeight(available: 300, count: 40, spacing: 6, footer: 24, maximum: 88) < 10)
        #expect(StripRowSizing.rowHeight(available: 100, count: 40, spacing: 6, footer: 24, maximum: 88) == 0)
    }

    @Test("サムネイルを出しているときは、上限を大きくする")
    func maximum() {
        #expect(StripRowSizing.maximumRowHeight(size: .thumbnail) > StripRowSizing.maximumRowHeight(size: .list))
    }

    @Test("一覧の行は、ウインドウの数にかかわらず決まった高さ（ブラウザの縦のタブと同じくらい）")
    func listRows() {
        let few = StripRowSizing.rowHeight(size: .list, available: 700, count: 2, footer: 0)
        let many = StripRowSizing.rowHeight(size: .list, available: 700, count: 40, footer: 0)
        #expect(few == StripRowSizing.listRowHeight)
        #expect(many == StripRowSizing.listRowHeight)
        // サムネイルは、少ないほど大きく広げる
        let thumbnail = StripRowSizing.rowHeight(size: .thumbnail, available: 700, count: 2, footer: 0)
        #expect(thumbnail > StripRowSizing.listRowHeight)
        // 一覧は、行の間も詰める
        #expect(StripRowSizing.spacing(size: .list) < StripRowSizing.spacing(size: .thumbnail))
    }
}

@Suite("アイコンの並びの並べ替え")
struct GridReorderTests {
    // 3 列 × 2 行（5 個）
    let frames: [Int: CGRect] = [
        0: CGRect(x: 0, y: 0, width: 40, height: 40),
        1: CGRect(x: 50, y: 0, width: 40, height: 40),
        2: CGRect(x: 100, y: 0, width: 40, height: 40),
        3: CGRect(x: 0, y: 50, width: 40, height: 40),
        4: CGRect(x: 50, y: 50, width: 40, height: 40),
    ]

    @Test("同じ行では、真ん中より左ならその前に入れる")
    func sameRow() {
        #expect(ListReorder.gridDropIndex(for: CGPoint(x: 10, y: 20), frames: frames, count: 5) == 0)
        #expect(ListReorder.gridDropIndex(for: CGPoint(x: 60, y: 20), frames: frames, count: 5) == 1)
        #expect(ListReorder.gridDropIndex(for: CGPoint(x: 130, y: 20), frames: frames, count: 5) == 3)
    }

    @Test("下の行・最後")
    func nextRow() {
        #expect(ListReorder.gridDropIndex(for: CGPoint(x: 60, y: 70), frames: frames, count: 5) == 4)
        #expect(ListReorder.gridDropIndex(for: CGPoint(x: 120, y: 70), frames: frames, count: 5) == 5)
        #expect(ListReorder.gridDropIndex(for: CGPoint(x: 10, y: 200), frames: frames, count: 5) == 5)
    }
}

@Suite("ストリップの見た目")
struct StripLookTests {
    @Test("サムネイルの見た目のときだけ、サムネイルを撮る")
    func thumbnails() {
        var settings = StripSettings.default
        settings.itemSize = .thumbnail
        #expect(settings.capturesThumbnails)
        for size in [StripItemSize.icons, .grid, .list] {
            settings.itemSize = size
            #expect(!settings.capturesThumbnails)
        }
    }

    @Test("見た目を 4 つにまとめる前の値は、まとめた先に読み替える")
    func storedValues() throws {
        #expect(StripItemSize(storedValue: "small") == .list)
        #expect(StripItemSize(storedValue: "medium") == .list)
        #expect(StripItemSize(storedValue: "thumbnailMedium") == .thumbnail)
        #expect(StripItemSize(storedValue: "thumbnailLarge") == .thumbnail)
        #expect(StripItemSize(storedValue: "grid") == .grid)
        #expect(StripItemSize(storedValue: "unknown") == nil)
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("thumbnailLarge", forKey: "strip.itemSize")
        #expect(StripSettings(defaults: defaults).itemSize == .thumbnail)
    }

    @Test("アイコンの並びは、ストリップの幅をそのまま使う")
    func gridWidth() {
        var settings = StripSettings.default
        settings.stripWidth = 300
        settings.itemSize = .grid
        #expect(settings.effectiveWidth == 300)
        #expect(settings.itemSize.showsTiles)
        #expect(!settings.itemSize.isIconOnly)
    }
}

@Suite("いまのデスクトップだけを見せているときの並べ替え")
struct SubsetReorderTests {
    // 全体は a b c d e。見えているのは a c e（b と d はほかのデスクトップ）
    let all = ["a", "b", "c", "d", "e"]
    let visible = ["a", "c", "e"]

    @Test("見えている行の前に入れる。見えていないものの並びは崩さない")
    func before() {
        // e を a の前へ
        #expect(ListReorder.movedSubset(all: all, visible: visible, from: 2, dropIndex: 0) == ["e", "a", "b", "c", "d"])
        // a を e の前へ
        #expect(ListReorder.movedSubset(all: all, visible: visible, from: 0, dropIndex: 2) == ["b", "c", "d", "a", "e"])
    }

    @Test("最後の行の後ろに入れる")
    func end() {
        #expect(ListReorder.movedSubset(all: all, visible: visible, from: 0, dropIndex: 3) == ["b", "c", "d", "e", "a"])
    }

    @Test("並びが変わらない位置・範囲の外では、そのまま")
    func noChange() {
        #expect(ListReorder.movedSubset(all: all, visible: visible, from: 1, dropIndex: 2) == all)
        #expect(ListReorder.movedSubset(all: all, visible: visible, from: 5, dropIndex: 0) == all)
    }

    @Test("全部見えているときは、ふつうの並べ替えと同じ")
    func allVisible() {
        #expect(ListReorder.movedSubset(all: all, visible: all, from: 0, dropIndex: 3) == ListReorder.moved(all, from: 0, dropIndex: 3))
    }
}

@Suite("ほかのデスクトップのウインドウ")
struct OtherSpacesSettingTests {
    @Test("初期設定は、いまのデスクトップだけ。保存して読み戻せる")
    func persistence() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = StripSettings(defaults: defaults)
        #expect(!settings.showsOtherSpaces)
        settings.showsOtherSpaces = true
        settings.save(to: defaults)
        #expect(StripSettings(defaults: defaults).showsOtherSpaces)
    }
}

@Suite("ウインドウのディスプレイ")
struct DisplayAssignmentTests {
    // 左に 1600×1000、右に 1920×1080 のディスプレイ
    let displays = [CGRect(x: 0, y: 0, width: 1600, height: 1000), CGRect(x: 1600, y: 0, width: 1920, height: 1080)]

    @Test("いちばん大きく重なっているディスプレイ")
    func overlap() {
        #expect(DisplayAssignment.displayIndex(for: CGRect(x: 100, y: 100, width: 500, height: 500), displays: displays) == 0)
        // 境目をまたいでいても、多く重なっているほう
        #expect(DisplayAssignment.displayIndex(for: CGRect(x: 1400, y: 100, width: 600, height: 500), displays: displays) == 1)
    }

    @Test("どこにも重なっていなければ、いちばん近いディスプレイ。ディスプレイがなければ nil")
    func outside() {
        #expect(DisplayAssignment.displayIndex(for: CGRect(x: 4000, y: 100, width: 300, height: 300), displays: displays) == 1)
        #expect(DisplayAssignment.displayIndex(for: CGRect(x: -900, y: 100, width: 300, height: 300), displays: displays) == 0)
        #expect(DisplayAssignment.displayIndex(for: .zero, displays: []) == nil)
    }

    @Test("ほかのディスプレイのウインドウも出す設定は、初期設定でオフ。保存して読み戻せる")
    func setting() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = StripSettings(defaults: defaults)
        #expect(!settings.showsOtherDisplays)
        settings.showsOtherDisplays = true
        settings.save(to: defaults)
        #expect(StripSettings(defaults: defaults).showsOtherDisplays)
    }
}
