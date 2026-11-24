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
    @Test("新しいものは末尾に足し、なくなったものは除く")
    func syncing() {
        #expect(RecentOrder.syncing([1, 2, 3], with: [3, 4, 1]) == [1, 3, 4])
    }

    @Test("新しいものは、同じアプリのウインドウの最後のすぐ後ろに入れる（なければ末尾）")
    func groupsSameApp() {
        // 1・3 は A、2 は B、4・5 は新しい A と C
        let apps = [1: "A", 2: "B", 3: "A", 4: "A", 5: "C"]
        let synced = RecentOrder.syncing([1, 2, 3], with: [5, 4, 3, 2, 1]) { apps[$0] }
        #expect(synced == [1, 2, 3, 4, 5])
        // A が離れて並んでいる（利用者が離した）ときは、最後の A の後ろに入れ、ほかは動かさない
        let apart = RecentOrder.syncing([1, 2, 3], with: [1, 2, 3, 4]) { apps[$0] }
        #expect(apart == [1, 2, 3, 4])
        let middle = RecentOrder.syncing([1, 2], with: [1, 2, 4]) { apps[$0] }
        #expect(middle == [1, 4, 2])
        // アプリが分からないものは末尾
        #expect(RecentOrder.syncing([1, 2], with: [1, 2, 9]) { apps[$0] } == [1, 2, 9])
    }

    @Test("同じアプリをまとめるときは、すでに並んでいるものも、最初に出てくる位置にまとめる")
    func clusters() {
        // A1, B, C, A2 → A1, A2, B, C（アプリどうしの順番・アプリの中の順番は変えない）
        let apps = ["a1": "A", "b": "B", "c": "C", "a2": "A", "x": nil] as [String: String?]
        let app: (String) -> String? = { apps[$0] ?? nil }
        #expect(RecentOrder.clustered(["a1", "b", "c", "a2"], app: app) == ["a1", "a2", "b", "c"])
        // アプリが分からないものは、その位置のまま
        #expect(RecentOrder.clustered(["x", "a1", "b", "a2"], app: app) == ["x", "a1", "a2", "b"])
        // 読み直すたびにまとめる（オフなら、そのまま）
        #expect(RecentOrder.syncing(["a1", "b", "a2"], with: ["a1", "b", "a2"], clusters: true, app: app) == ["a1", "a2", "b"])
        #expect(RecentOrder.syncing(["a1", "b", "a2"], with: ["a1", "b", "a2"], clusters: false, app: app) == ["a1", "b", "a2"])
    }

    @Test("同じアプリをまとめるときのドラッグ: ほかのアプリの間へはまとめて動かし、同じアプリの中では順番を変える")
    func movesCluster() {
        let apps = ["a1": "A", "a2": "A", "b": "B", "c": "C"]
        let app: (String) -> String? = { apps[$0] }
        let all = ["a1", "a2", "b", "c"]
        // a2 を c の後ろへ → A がまとめて c の後ろへ
        #expect(ListReorder.movedSubset(all: all, visible: all, from: 1, dropIndex: 4, clusteringBy: app) == ["b", "c", "a1", "a2"])
        // a1 を b と c の間へ → A がまとめて動く
        #expect(ListReorder.movedSubset(all: all, visible: all, from: 0, dropIndex: 3, clusteringBy: app) == ["b", "a1", "a2", "c"])
        // a2 を a1 の前へ → A の中で入れ替わる
        #expect(ListReorder.movedSubset(all: all, visible: all, from: 1, dropIndex: 0, clusteringBy: app) == ["a2", "a1", "b", "c"])
        // c を先頭へ → c だけ動く
        #expect(ListReorder.movedSubset(all: all, visible: all, from: 3, dropIndex: 0, clusteringBy: app) == ["c", "a1", "a2", "b"])
        // 動かないところに落としたら、そのまま
        #expect(ListReorder.movedSubset(all: all, visible: all, from: 2, dropIndex: 3, clusteringBy: app) == all)
    }

    @Test("となり合った同じアプリの行の範囲（1 つだけなら nil）")
    func clusterRange() {
        let keys = ["A", "A", "B", "C", "C", "C"]
        #expect(ListReorder.cluster(at: 0, keys: keys) == 0...1)
        #expect(ListReorder.cluster(at: 1, keys: keys) == 0...1)
        #expect(ListReorder.cluster(at: 2, keys: keys) == nil)
        #expect(ListReorder.cluster(at: 4, keys: keys) == 3...5)
        #expect(ListReorder.cluster(at: 9, keys: keys) == nil)
    }

    @Test("まとめているときに落とせる位置: 自分のまとまりの中・すぐ前後と、ほかのアプリのまとまりの中には落とせない")
    func clusterDrops() {
        let keys = ["A", "A", "B", "C", "C"]
        // A のまとまり（0...1）をドラッグしているとき
        for drop in 0...2 { #expect(!ListReorder.canDrop(at: drop, keys: keys, cluster: 0...1)) }
        // B と C の間・末尾には落とせる。C のまとまりの中（4 の前）には落とせない
        #expect(ListReorder.canDrop(at: 3, keys: keys, cluster: 0...1))
        #expect(!ListReorder.canDrop(at: 4, keys: keys, cluster: 0...1))
        #expect(ListReorder.canDrop(at: 5, keys: keys, cluster: 0...1))
        // 1 つだけの B（まとまりなし）は、A の中・C の中には落とせず、先頭・末尾・まとまりの境目には落とせる
        #expect(ListReorder.canDrop(at: 0, keys: keys, cluster: nil))
        #expect(!ListReorder.canDrop(at: 1, keys: keys, cluster: nil))
        #expect(ListReorder.canDrop(at: 2, keys: keys, cluster: nil))
        #expect(!ListReorder.canDrop(at: 4, keys: keys, cluster: nil))
        #expect(ListReorder.canDrop(at: 5, keys: keys, cluster: nil))
    }

    @Test("同じアプリをまとめるかは、初期設定はオン。保存して読み戻せる")
    func groupsSameAppSetting() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = StripSettings(defaults: defaults)
        #expect(settings.groupsSameApp)
        settings.groupsSameApp = false
        settings.save(to: defaults)
        #expect(!StripSettings(defaults: defaults).groupsSameApp)
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

    @Test("横に並べたときは、ポインタの x から、落とす位置を決める（真ん中より左なら、その前）")
    func horizontalDropIndex() {
        let columns: [Int: CGRect] = [
            0: CGRect(x: 0, y: 0, width: 120, height: 34),
            1: CGRect(x: 124, y: 0, width: 120, height: 34),
            2: CGRect(x: 248, y: 0, width: 120, height: 34),
        ]
        #expect(ListReorder.dropIndex(forX: -10, frames: columns, count: 3) == 0)
        #expect(ListReorder.dropIndex(forX: 100, frames: columns, count: 3) == 1)
        #expect(ListReorder.dropIndex(forX: 190, frames: columns, count: 3) == 2)
        #expect(ListReorder.dropIndex(forX: 900, frames: columns, count: 3) == 3)
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
    @Test("アイコンの並びの列の数は、タイルのいちばん小さい幅で入るだけ（狭くても 1 列）")
    func gridColumns() {
        // (230 + 6) ÷ (50 + 6) ≒ 4.2 → 4 列
        #expect(StripRowSizing.gridColumns(width: 230, tileWidth: 50, spacing: 6) == 4)
        // ちょうど入る幅（50×2 + 6）
        #expect(StripRowSizing.gridColumns(width: 106, tileWidth: 50, spacing: 6) == 2)
        #expect(StripRowSizing.gridColumns(width: 105, tileWidth: 50, spacing: 6) == 1)
        #expect(StripRowSizing.gridColumns(width: 30, tileWidth: 50, spacing: 6) == 1)
        // まだ幅が分からないとき
        #expect(StripRowSizing.gridColumns(width: 0, tileWidth: 50, spacing: 6) == 1)
    }

    @Test("アイコンの格子は、複数の列なら左右に余白を空ける。余白で列が減るとき・1 列のときは空けない")
    func gridLayout() {
        // 230pt に 4 列。余白 4pt ずつを空けても 4 列のまま
        #expect(StripRowSizing.gridLayout(width: 230, tileWidth: 50, spacing: 6, sideMargin: 4) == .init(columns: 4, sideMargin: 4))
        // ちょうど 2 列入る幅。余白を空けると 1 列になるので、空けずに 2 列
        #expect(StripRowSizing.gridLayout(width: 106, tileWidth: 50, spacing: 6, sideMargin: 4) == .init(columns: 2, sideMargin: 0))
        // 1 列（細い帯）は、線が横なので空けない
        #expect(StripRowSizing.gridLayout(width: 52, tileWidth: 50, spacing: 6, sideMargin: 4) == .init(columns: 1, sideMargin: 0))
    }

    @Test("格子の行の右端（同じアプリのまとまりは、そこで次の行へ折り返す）")
    func lineEnd() {
        #expect(StripRowSizing.isLineEnd(2, columns: 3))
        #expect(StripRowSizing.isLineEnd(5, columns: 3))
        #expect(!StripRowSizing.isLineEnd(3, columns: 3))
        #expect(!StripRowSizing.isLineEnd(0, columns: 3))
        // 1 列は、縦に続くので端はない
        #expect(!StripRowSizing.isLineEnd(0, columns: 1))
        #expect(!StripRowSizing.isLineEnd(4, columns: 1))
    }

    @Test("一覧の行は、ウインドウの数にかかわらず決まった高さ（ブラウザの縦のタブと同じくらい）")
    func listRows() {
        #expect(StripRowSizing.rowHeight(kind: .list(.small)) == 34)
        // サムネイルは、ウインドウが少なくても縦いっぱいには広げず、中身の高さのまま（0）
        for size in StripIconSize.allCases {
            #expect(StripRowSizing.rowHeight(kind: .thumbnail(size)) == 0)
        }
        // 一覧は、行の間も詰める
        #expect(StripRowSizing.spacing(kind: .list(.small)) < StripRowSizing.spacing(kind: .thumbnail(.small)))
    }

    @Test("アイコンの並びは、アイコンの大きさで決まった高さ。小さなアイコンは、一覧と同じ大きさで、間も詰める")
    func tileRows() {
        for size in StripIconSize.allCases {
            let kind = StripRowKind.tile(size)
            #expect(StripRowSizing.rowHeight(kind: kind) == size.tileHeight)
            #expect(kind.iconSize == size.iconSize)
            #expect(kind.showsIconOnly)
            // タイルにアイコンが収まる
            #expect(size.tileHeight > size.iconSize && size.tileWidth > size.iconSize)
        }
        #expect(StripRowKind.tile(.small).iconSize == StripRowKind.list(.small).iconSize)
        #expect(StripIconSize.large.iconSize == 36)
        #expect(StripRowSizing.spacing(kind: .tile(.small)) < StripRowSizing.spacing(kind: .tile(.large)))
        #expect(!StripRowKind.list(.small).showsIconOnly)
    }

    @Test("大きさは、一覧・サムネイルにもかかる（「小」は、いままでの大きさ。大きいほど大きい）")
    func sizeAppliesToEveryFormat() {
        // 「小」は、いままでの一覧（ブラウザの縦のタブ）とサムネイルの大きさ
        #expect(StripIconSize.small.listRowHeight == 34)
        #expect(StripIconSize.small.listIconSize == 18)
        #expect(StripIconSize.small.thumbnailHeight == 84)
        let sizes = StripIconSize.allCases
        for (smaller, larger) in zip(sizes, sizes.dropFirst()) {
            #expect(smaller.listRowHeight < larger.listRowHeight)
            #expect(smaller.listIconSize < larger.listIconSize)
            #expect(smaller.listFontSize < larger.listFontSize)
            #expect(smaller.thumbnailHeight < larger.thumbnailHeight)
            #expect(smaller.thumbnailBadgeSize < larger.thumbnailBadgeSize)
            #expect(StripRowSizing.barThickness(kind: .list(smaller)) < StripRowSizing.barThickness(kind: .list(larger)))
            #expect(StripRowSizing.barThickness(kind: .thumbnail(smaller)) < StripRowSizing.barThickness(kind: .thumbnail(larger)))
        }
        for size in sizes {
            // 一覧の行は、大きさで決まった高さ。アイコンが収まる
            #expect(StripRowSizing.rowHeight(kind: .list(size)) == size.listRowHeight)
            #expect(size.listIconSize < size.listRowHeight)
        }
        // 横長の帯でも、「小」はいままでの大きさ
        #expect(StripRowSizing.barRowHeight(kind: .thumbnail(.small)) == 116)
        #expect(StripRowSizing.barItemWidth(kind: .thumbnail(.small), available: 1000, count: 3) == 150)
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
        for size in [StripItemSize.grid, .list] {
            settings.itemSize = size
            #expect(!settings.capturesThumbnails)
        }
    }

    @Test("行の描き方は、形式と大きさで決まる")
    func rowKind() {
        var settings = StripSettings.default
        settings.itemSize = .thumbnail
        #expect(settings.rowKind == .thumbnail(.small))
        settings.itemSize = .list
        #expect(settings.rowKind == .list(.small))
        settings.iconSize = .large
        #expect(settings.rowKind == .list(.large))
        settings.itemSize = .grid
        #expect(settings.rowKind == .tile(.large))
        settings.iconSize = .small
        #expect(settings.rowKind == .tile(.small))
    }

    @Test("大きさは保存して読み戻せる（初期設定は小。アイコンの並びだけにかけていたときの値も読む）")
    func iconSizePersistence() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("large", forKey: "strip.gridIconSize")
        #expect(StripSettings(defaults: defaults).iconSize == .large)
        defaults.removePersistentDomain(forName: suite)
        var settings = StripSettings(defaults: defaults)
        #expect(settings.iconSize == .small)
        settings.iconSize = .medium
        settings.save(to: defaults)
        #expect(StripSettings(defaults: defaults).iconSize == .medium)
    }

    @Test("見た目を 4 つにまとめる前の値は、まとめた先に読み替える")
    func storedValues() throws {
        #expect(StripItemSize(storedValue: "small") == .list)
        #expect(StripItemSize(storedValue: "medium") == .list)
        #expect(StripItemSize(storedValue: "thumbnailMedium") == .thumbnail)
        #expect(StripItemSize(storedValue: "thumbnailLarge") == .thumbnail)
        #expect(StripItemSize(storedValue: "grid") == .grid)
        // 前の「細い帯」は、アイコンの並び
        #expect(StripItemSize(storedValue: "icons") == .grid)
        #expect(StripItemSize(storedValue: "unknown") == nil)
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("thumbnailLarge", forKey: "strip.itemSize")
        #expect(StripSettings(defaults: defaults).itemSize == .thumbnail)
    }

    @Test("アイコンの並びの幅は、一覧・サムネイルの幅とは別に覚える")
    func gridWidth() {
        var settings = StripSettings.default
        settings.stripWidth = 300
        settings.itemSize = .grid
        // 何も変えていなければ、初期設定の幅
        #expect(settings.effectiveThickness == StripGeometry.defaultWidth)
        settings.width = 90
        #expect(settings.effectiveThickness == 90)
        #expect(settings.rowKind.showsIconOnly)
        // 一覧に戻すと、一覧の幅に戻る。アイコンの並びにすると、狭めた幅に戻る
        settings.itemSize = .list
        #expect(settings.effectiveThickness == 300)
        settings.width = 200
        #expect(settings.stripWidth == 200)
        settings.itemSize = .grid
        #expect(settings.effectiveThickness == 90)
    }

    @Test("アイコンの並びは、1 列になる幅まで狭められる（一覧・サムネイルは、ふつうの下限まで）")
    func oneColumn() throws {
        var settings = StripSettings.default
        settings.itemSize = .grid
        for size in StripIconSize.allCases {
            settings.iconSize = size
            settings.width = 10
            #expect(settings.width == size.minimumStripWidth)
            #expect(settings.widthRange.lowerBound == size.minimumStripWidth)
            // 1 列のタイルと、両側の余白が収まる
            #expect(size.minimumStripWidth >= size.tileWidth + 12)
            // 細い帯の形で描く
            #expect(StripGeometry.usesCompactChrome(width: settings.width))
        }
        // 小さなアイコンで狭めたあと、大きくしたら、その大きさの 1 列の幅まで広げる
        settings.iconSize = .small
        settings.width = 10
        settings.iconSize = .large
        #expect(settings.width == StripIconSize.large.minimumStripWidth)
        // 一覧は、ふつうの下限まで
        settings.itemSize = .list
        settings.width = 10
        #expect(settings.width == StripGeometry.widthRange.lowerBound)
        #expect(!StripGeometry.usesCompactChrome(width: settings.width))
        // 狭めた幅は、保存して読み戻せる
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        settings.itemSize = .grid
        settings.iconSize = .small
        settings.width = 52
        settings.save(to: defaults)
        #expect(StripSettings(defaults: defaults).width == 52)
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
}
