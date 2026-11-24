import CoreGraphics
import Foundation
import Testing
@testable import PinstageCore

@Suite("ウインドウの照合")
struct WindowMatcherTests {
    let safari = "com.apple.Safari"
    let code = "com.microsoft.VSCode"

    @Test("名前がぴったり同じウインドウを先に当てはめる")
    func exactTitle() {
        let result = WindowMatcher.match(
            [WindowSignature(bundleID: safari, title: "資料")],
            candidates: [WindowSignature(bundleID: safari, title: "ニュース"), WindowSignature(bundleID: safari, title: "資料")],
            runningBundleIDs: [safari]
        )
        #expect(result == [.window(1)])
    }

    @Test("名前が変わっていても、同じアプリのウインドウに当てはめる。同じウインドウは 2 回使わない")
    func sameApp() {
        let result = WindowMatcher.match(
            [WindowSignature(bundleID: safari, title: "古い名前"), WindowSignature(bundleID: safari, title: "資料")],
            candidates: [WindowSignature(bundleID: safari, title: "資料"), WindowSignature(bundleID: safari, title: "別")],
            runningBundleIDs: [safari]
        )
        #expect(result == [.window(1), .window(0)])
    }

    @Test("アプリが動いていなければ起動し直す、動いていてウインドウがなければ見つからない")
    func missing() {
        let result = WindowMatcher.match(
            [WindowSignature(bundleID: code, title: "x"), WindowSignature(bundleID: safari, title: "y")],
            candidates: [],
            runningBundleIDs: [safari]
        )
        #expect(result == [.appNotRunning, .missingWindow])
    }
}

@Suite("保存")
struct PersistenceTests {
    func temporaryStore() -> StageLibraryStore {
        let dir = FileManager.default.temporaryDirectory.appending(path: "PinstageTests-\(UUID().uuidString)")
        return StageLibraryStore(fileURL: dir.appending(path: "library.json"))
    }

    @Test("まだ保存していなければ空")
    func emptyLoad() throws {
        #expect(try temporaryStore().load() == StageLibrary())
    }

    @Test("グループと型を書いて、同じものを読み戻せる")
    func roundTrip() throws {
        let store = temporaryStore()
        let layout = CustomLayout(name: "マイ型 1", slots: [UnitRect(x: 0, y: 0, width: 0.6, height: 1)])
        let group = StageGroup(
            name: "開発",
            members: [WindowSignature(bundleID: "com.apple.Safari", title: "資料")],
            layout: .custom(layout.id),
            displayID: "DISPLAY-UUID"
        )
        let library = StageLibrary(groups: [group], customLayouts: [layout])
        try store.save(library)
        #expect(try store.load() == library)
    }

    @Test("用意した型の選び方も読み戻せる")
    func builtInChoice() throws {
        let data = try JSONEncoder().encode(LayoutChoice.builtIn(.mainLeft))
        #expect(try JSONDecoder().decode(LayoutChoice.self, from: data) == .builtIn(.mainLeft))
    }
}

@Suite("ストリップ")
struct StripTests {
    let visible = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    @Test("常に出すときは、ストリップの右側だけをステージにする")
    func stageAlwaysShown() {
        let stage = StripGeometry.stageFrame(in: visible, mode: .alwaysShown, edge: .left, thickness: 230)
        let strip = StripGeometry.shownFrame(in: visible, edge: .left, thickness: 230)
        #expect(stage.minX == strip.maxX + StripGeometry.stageGap)
        #expect(stage.maxX == visible.maxX)
    }

    @Test("ストリップは、ステージと同じく上下いっぱいを使う")
    func fullHeight() {
        let strip = StripGeometry.shownFrame(in: visible, edge: .left, thickness: 230)
        let stage = StripGeometry.stageFrame(in: visible, mode: .alwaysShown, edge: .left, thickness: 230)
        #expect(strip.minY == visible.minY)
        #expect(strip.maxY == visible.maxY)
        #expect(strip.minY == stage.minY && strip.maxY == stage.maxY)
    }

    @Test("自動で隠すときは、どの辺でも、画面いっぱいをステージにする", arguments: StripEdge.allCases)
    func stageAutoHide(edge: StripEdge) {
        #expect(StripGeometry.stageFrame(in: visible, mode: .autoHide, edge: edge, thickness: 230) == visible)
    }

    @Test("左端にポインタが来たら出し、離れたら隠す")
    func revealAndHide() {
        #expect(StripGeometry.shouldReveal(pointer: CGPoint(x: 1, y: 500), screenFrame: visible, edge: .left))
        #expect(!StripGeometry.shouldReveal(pointer: CGPoint(x: 50, y: 500), screenFrame: visible, edge: .left))
        // 左隣のディスプレイの上では出さない
        let right = CGRect(x: 1600, y: 0, width: 1600, height: 1000)
        #expect(!StripGeometry.shouldReveal(pointer: CGPoint(x: 800, y: 500), screenFrame: right, edge: .left))
        #expect(StripGeometry.shouldReveal(pointer: CGPoint(x: 1601, y: 500), screenFrame: right, edge: .left))
        let strip = StripGeometry.shownFrame(in: visible, edge: .left, thickness: 230)
        #expect(!StripGeometry.shouldHide(pointer: CGPoint(x: strip.maxX + 10, y: 500), stripFrame: strip, screenFrame: visible, edge: .left))
        #expect(StripGeometry.shouldHide(pointer: CGPoint(x: strip.maxX + 100, y: 500), stripFrame: strip, screenFrame: visible, edge: .left))
    }

    @Test("幅を変えると、ストリップとステージの境目も動く")
    func width() {
        let strip = StripGeometry.shownFrame(in: visible, edge: .left, thickness: 320)
        let stage = StripGeometry.stageFrame(in: visible, mode: .alwaysShown, edge: .left, thickness: 320)
        #expect(strip.width == 320)
        #expect(stage.minX == strip.maxX + StripGeometry.stageGap)
        #expect(StripGeometry.hiddenFrame(in: visible, edge: .left, thickness: 320).maxX < visible.minX)
    }

    @Test("ドラッグの幅は範囲の中に収め、画面の半分より広くしない")
    func dragWidth() {
        #expect(StripGeometry.width(forPointerX: 300, in: visible, edge: .left) == 300 - StripGeometry.edgeMargin)
        #expect(StripGeometry.width(forPointerX: 20, in: visible, edge: .left) == StripGeometry.widthRange.lowerBound)
        #expect(StripGeometry.width(forPointerX: 2000, in: visible, edge: .left) == StripGeometry.widthRange.upperBound)
        let narrow = CGRect(x: 0, y: 0, width: 600, height: 800)
        #expect(StripGeometry.width(forPointerX: 500, in: narrow, edge: .left) == 300)
        // 右のストリップは、右端からの距離で決める（左へドラッグすると広がる）
        #expect(StripGeometry.width(forPointerX: 1300, in: visible, edge: .right) == 300 - StripGeometry.edgeMargin)
        #expect(StripGeometry.width(forPointerX: 1590, in: visible, edge: .right) == StripGeometry.widthRange.lowerBound)
    }

    @Test("どの辺でも、ストリップとステージは重ならず、合わせて使える範囲に収まる", arguments: StripEdge.allCases)
    func edges(edge: StripEdge) {
        // メニューバー（上 25pt）と Dock（下 70pt）を除いた範囲
        let visible = CGRect(x: 0, y: 70, width: 1600, height: 905)
        let strip = StripGeometry.shownFrame(in: visible, edge: edge, thickness: 200)
        let stage = StripGeometry.stageFrame(in: visible, mode: .alwaysShown, edge: edge, thickness: 200)
        #expect(visible.contains(strip))
        #expect(visible.contains(stage))
        #expect(!strip.intersects(stage))
        // 厚みは、左右なら幅、上下なら高さ。長さは、使える範囲いっぱい
        #expect((edge.isHorizontal ? strip.height : strip.width) == 200)
        #expect((edge.isHorizontal ? strip.width : strip.height) == (edge.isHorizontal ? visible.width : visible.height))
        // ステージは、ストリップと両側の間の分だけ狭くなる
        let used = 200 + StripGeometry.edgeMargin + StripGeometry.stageGap
        #expect(stage.width == visible.width - (edge.isHorizontal ? 0 : used))
        #expect(stage.height == visible.height - (edge.isHorizontal ? used : 0))
        // 隠すときは、使える範囲の外へ出す
        #expect(!StripGeometry.hiddenFrame(in: visible, edge: edge, thickness: 200).intersects(visible))
    }

    @Test("ストリップは、その辺に寄せて置く")
    func edgePlacement() {
        let visible = CGRect(x: 0, y: 70, width: 1600, height: 905)
        #expect(StripGeometry.shownFrame(in: visible, edge: .right, thickness: 200).maxX == visible.maxX - StripGeometry.edgeMargin)
        #expect(StripGeometry.stageFrame(in: visible, mode: .alwaysShown, edge: .right, thickness: 200).minX == visible.minX)
        // 画面座標は左下が原点。上の辺は maxY（メニューバーのすぐ下）、下の辺は minY（Dock のすぐ上）
        #expect(StripGeometry.shownFrame(in: visible, edge: .top, thickness: 48).maxY == visible.maxY - StripGeometry.edgeMargin)
        #expect(StripGeometry.stageFrame(in: visible, mode: .alwaysShown, edge: .top, thickness: 48).minY == visible.minY)
        #expect(StripGeometry.shownFrame(in: visible, edge: .bottom, thickness: 48).minY == visible.minY + StripGeometry.edgeMargin)
        #expect(StripGeometry.stageFrame(in: visible, mode: .alwaysShown, edge: .bottom, thickness: 48).maxY == visible.maxY)
    }

    @Test("ストリップのある端に寄せたときだけ出す")
    func revealOnEachEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let points: [StripEdge: CGPoint] = [
            .left: CGPoint(x: 0, y: 500), .right: CGPoint(x: 1599, y: 500),
            .top: CGPoint(x: 800, y: 1000), .bottom: CGPoint(x: 800, y: 1),
        ]
        for edge in StripEdge.allCases {
            for (at, point) in points {
                #expect(StripGeometry.shouldReveal(pointer: point, screenFrame: screen, edge: edge) == (at == edge))
            }
        }
        // 右隣・上隣のディスプレイの上では出さない
        #expect(!StripGeometry.shouldReveal(pointer: CGPoint(x: 1601, y: 500), screenFrame: screen, edge: .right))
        #expect(!StripGeometry.shouldReveal(pointer: CGPoint(x: 800, y: 1001), screenFrame: screen, edge: .top))
    }

    @Test("ストリップと画面の端との間（Dock・メニューバーのあるところ）にポインタがある間は、隠さない")
    func keepsShownOverSystemBar() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        // 下に Dock（70pt）、上にメニューバー（25pt）が常に出ている
        let visible = CGRect(x: 0, y: 70, width: 1600, height: 905)
        let bottom = StripGeometry.shownFrame(in: visible, edge: .bottom, thickness: 48)
        // 下の端に寄せて出した直後（ポインタは Dock の上。ストリップからは 24pt より離れている）
        #expect(!StripGeometry.shouldHide(pointer: CGPoint(x: 800, y: 1), stripFrame: bottom, screenFrame: screen, edge: .bottom))
        #expect(StripGeometry.shouldHide(pointer: CGPoint(x: 800, y: bottom.maxY + 100), stripFrame: bottom, screenFrame: screen, edge: .bottom))
        let top = StripGeometry.shownFrame(in: visible, edge: .top, thickness: 48)
        #expect(!StripGeometry.shouldHide(pointer: CGPoint(x: 800, y: 1000), stripFrame: top, screenFrame: screen, edge: .top))
        #expect(StripGeometry.shouldHide(pointer: CGPoint(x: 800, y: top.minY - 100), stripFrame: top, screenFrame: screen, edge: .top))
        // ほかの辺の端までは伸ばさない
        #expect(StripGeometry.shouldHide(pointer: CGPoint(x: 800, y: 1), stripFrame: top, screenFrame: screen, edge: .top))
    }

    @Test("上下に出したときの厚みは、行の描き方で決まる（幅の設定は使わない）")
    func barThickness() {
        var settings = StripSettings(mode: .alwaysShown, itemSize: .list, displays: .all, stripWidth: 300)
        #expect(settings.effectiveThickness == 300)
        settings.edge = .bottom
        #expect(settings.effectiveThickness == StripRowSizing.barThickness(kind: .list(.small)))
        settings.itemSize = .thumbnail
        #expect(settings.effectiveThickness == StripRowSizing.barThickness(kind: .thumbnail(.small)))
        // アイコンの並びも、大きさで決まる（小さいほど低い）
        settings.itemSize = .grid
        settings.iconSize = .small
        let small = settings.effectiveThickness
        settings.iconSize = .large
        #expect(small < settings.effectiveThickness)
        #expect(settings.effectiveThickness == StripRowSizing.barThickness(kind: .tile(.large)))
        settings.itemSize = .list
        settings.edge = .right
        #expect(settings.effectiveThickness == 300)
    }

    @Test("横長の帯の一覧は、使える幅をタブで分ける（範囲の中で）")
    func barItemWidth() {
        let range = StripRowSizing.tabWidthRange(for: .small)
        // 少ないときは上限の幅
        #expect(StripRowSizing.barItemWidth(kind: .list(.small), available: 1000, count: 2) == range.upperBound)
        // 多いときは同じ幅で分ける（間の 4pt を除く）
        #expect(StripRowSizing.barItemWidth(kind: .list(.small), available: 1000, count: 6) == 163)
        // 収まらないほど多いときは下限の幅（スクロールする）
        #expect(StripRowSizing.barItemWidth(kind: .list(.small), available: 1000, count: 20) == range.lowerBound)
        // 大きいほど、タブも広い
        #expect(StripRowSizing.barItemWidth(kind: .list(.large), available: 1000, count: 20) > range.lowerBound)
        // アイコン・サムネイルは決まった幅
        #expect(StripRowSizing.barItemWidth(kind: .thumbnail(.small), available: 1000, count: 20) == 150)
    }

    @Test("ステージとの間は設定で変えられる（初期設定は 8pt。範囲に収める。保存して読み戻せる）")
    func stageGapSetting() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = StripSettings(defaults: defaults)
        #expect(settings.stageGap == 8)
        settings.stageGap = 100
        #expect(settings.stageGap == StripGeometry.stageGapRange.upperBound)
        settings.stageGap = 4
        settings.save(to: defaults)
        #expect(StripSettings(defaults: defaults).stageGap == 4)
        // ステージは、ウインドウバーの横から、その間だけ空けた位置から
        let visible = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let strip = StripGeometry.shownFrame(in: visible, edge: .left, thickness: 200)
        #expect(strip.minX == visible.minX)
        #expect(StripGeometry.stageFrame(in: visible, mode: .alwaysShown, edge: .left, thickness: 200, gap: 4).minX == strip.maxX + 4)
        #expect(StripGeometry.stageFrame(in: visible, mode: .alwaysShown, edge: .left, thickness: 200, gap: 0).minX == strip.maxX)
    }

    @Test("位置は保存して読み戻せる（初期設定は左）")
    func edgePersistence() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = StripSettings(defaults: defaults)
        #expect(settings.edge == .left)
        settings.edge = .bottom
        settings.save(to: defaults)
        #expect(StripSettings(defaults: defaults).edge == .bottom)
    }

    @Test("同じ辺に、自動で隠れる Dock・メニューバーがあるときだけ、重なると知らせる")
    func edgeConflict() {
        #expect(StripEdgeConflict.dockEdge(orientation: "left") == .left)
        #expect(StripEdgeConflict.dockEdge(orientation: "right") == .right)
        #expect(StripEdgeConflict.dockEdge(orientation: "bottom") == .bottom)
        #expect(StripEdgeConflict.dockEdge(orientation: nil) == .bottom)
        // 自動で隠れる Dock と同じ辺
        #expect(StripEdgeConflict.conflict(edge: .bottom, dockEdge: .bottom, dockAutoHides: true, menuBarAutoHides: false) == .autoHidingDock)
        // 常に出ている Dock は、使える範囲から除かれているので重ならない
        #expect(StripEdgeConflict.conflict(edge: .bottom, dockEdge: .bottom, dockAutoHides: false, menuBarAutoHides: false) == nil)
        // ほかの辺の Dock は関係ない
        #expect(StripEdgeConflict.conflict(edge: .left, dockEdge: .bottom, dockAutoHides: true, menuBarAutoHides: true) == nil)
        // 上の辺は、メニューバーが自動で隠れるとき
        #expect(StripEdgeConflict.conflict(edge: .top, dockEdge: .bottom, dockAutoHides: true, menuBarAutoHides: true) == .autoHidingMenuBar)
        #expect(StripEdgeConflict.conflict(edge: .top, dockEdge: .bottom, dockAutoHides: true, menuBarAutoHides: false) == nil)
    }

    @Test("幅は保存して読み戻せる")
    func widthPersistence() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = StripSettings(defaults: defaults)
        #expect(settings.stripWidth == StripGeometry.defaultWidth)
        settings.stripWidth = 1000
        #expect(settings.stripWidth == StripGeometry.widthRange.upperBound)
        settings.stripWidth = 300
        settings.save(to: defaults)
        #expect(StripSettings(defaults: defaults).stripWidth == 300)
    }

    @Test("アイコンの並びをドラッグで狭めるときは、1 列になる幅まで")
    func dragGridWidth() {
        var settings = StripSettings.default
        settings.itemSize = .grid
        settings.iconSize = .small
        #expect(StripGeometry.width(forPointerX: 20, in: visible, edge: .left, range: settings.widthRange) == StripIconSize.small.minimumStripWidth)
        #expect(StripGeometry.width(forPointerX: 100 + StripGeometry.edgeMargin, in: visible, edge: .left, range: settings.widthRange) == 100)
    }

    @Test("座標の向きを変換して、元に戻せる")
    func coordinates() {
        let rect = CGRect(x: 10, y: 100, width: 200, height: 300)
        let ax = ScreenCoordinates.toAccessibility(rect, primaryScreenHeight: 1000)
        #expect(ax == CGRect(x: 10, y: 600, width: 200, height: 300))
        // 向きを折り返すだけなので、もう一度かけると元に戻る
        #expect(ScreenCoordinates.toAccessibility(ax, primaryScreenHeight: 1000) == rect)
    }
}

@Suite("自動化の URL")
struct PinstageURLTests {
    func parse(_ text: String) -> PinstageCommand? {
        URL(string: text).flatMap(PinstageURL.parse)
    }

    @Test("グループを名前で呼び出す（日本語の名前も）")
    func group() throws {
        let url = try #require(PinstageURL.groupURL(name: "資料 作り"))
        #expect(PinstageURL.parse(url) == .recallGroup("資料 作り"))
        #expect(parse("pinstage://group/dev") == .recallGroup("dev"))
        #expect(parse("pinstage://group/next") == .nextGroup)
        #expect(parse("pinstage://group/previous") == .previousGroup)
        #expect(parse("pinstage://group/") == nil)
    }

    @Test("ストリップ・検索・保存")
    func others() {
        #expect(parse("pinstage://strip/show") == .strip(.show))
        #expect(parse("pinstage://strip/HIDE") == .strip(.hide))
        #expect(parse("pinstage://strip") == .strip(.toggle))
        #expect(parse("pinstage://strip/unknown") == nil)
        #expect(parse("pinstage://search") == .search)
        #expect(parse("pinstage://save?name=%E9%96%8B%E7%99%BA") == .saveStageAsGroup(name: "開発"))
        #expect(parse("pinstage://save") == .saveStageAsGroup(name: nil))
    }

    @Test("ほかの URL は受け取らない")
    func otherScheme() {
        #expect(parse("https://example.com/group/dev") == nil)
        #expect(parse("pinstage://unknown") == nil)
    }
}

@Suite("グループを名前で探す")
struct GroupLookupTests {
    let dev = StageGroup(name: "開発", members: [], layout: .builtIn(.auto), displayID: nil)
    let docs = StageGroup(name: "Docs", members: [], layout: .builtIn(.auto), displayID: nil)

    @Test("ID・ぴったり同じ名前・違いを除いて同じ名前の順に探す")
    func lookup() {
        let library = StageLibrary(groups: [dev, docs])
        #expect(library.group(matching: dev.id.uuidString)?.id == dev.id)
        #expect(library.group(matching: "開発")?.id == dev.id)
        #expect(library.group(matching: "ｄｏｃｓ")?.id == docs.id)
        #expect(library.group(matching: "ない") == nil)
        #expect(library.group(matching: "  ") == nil)
    }
}

@Suite("自動で隠すときの決まり")
struct StripAutoHideTests {
    /// ポインタの位置を順に渡したときの、隠すかどうかの並び
    func run(_ rule: inout StripAutoHide, _ positions: [Bool]) -> [Bool] {
        positions.map { rule.shouldHide(pointerNear: $0) }
    }

    @Test("左端に寄せて出したときは、離れたら隠す")
    func normal() {
        var rule = StripAutoHide()
        let results = run(&rule, [true, false])
        #expect(results == [false, true])
    }

    @Test("キーで出したときは、離れたところにポインタがあっても隠さない。一度入って離れたら隠す")
    func heldOpen() {
        var rule = StripAutoHide()
        rule.holdOpen()
        let results = run(&rule, [false, false, true, false])
        #expect(results == [false, false, false, true])
        // 隠したあとは、ふつうの決まりに戻る
        #expect(!rule.isHeldOpen)
    }
}

@Suite("グループの中身をドラッグで直す")
struct GroupMemberEditingTests {
    let safari = WindowSignature(bundleID: "com.apple.Safari", title: "資料")
    let code = WindowSignature(bundleID: "com.microsoft.VSCode", title: "app")

    func library() -> (StageLibrary, UUID, UUID) {
        let dev = StageGroup(name: "開発", members: [safari], layout: .builtIn(.auto), displayID: nil)
        let docs = StageGroup(name: "資料", members: [code], layout: .builtIn(.auto), displayID: nil)
        return (StageLibrary(groups: [dev, docs]), dev.id, docs.id)
    }

    @Test("足す。もう入っていれば足さない")
    func add() {
        var (library, dev, _) = library()
        let first = library.addMember(code, toGroup: dev)
        let second = library.addMember(code, toGroup: dev)
        #expect(first)
        #expect(!second)
        #expect(library.groups[0].members == [safari, code])
    }

    @Test("外す")
    func remove() {
        var (library, dev, _) = library()
        let removed = library.removeMember(at: 0, fromGroup: dev)
        let outOfRange = library.removeMember(at: 5, fromGroup: dev)
        #expect(removed == safari)
        #expect(library.groups[0].members.isEmpty)
        #expect(outOfRange == nil)
    }

    @Test("ほかのグループへ移す。移す先に入っていれば、元から外すだけ")
    func move() {
        var (library, dev, docs) = library()
        let moved = library.moveMember(at: 0, from: dev, to: docs)
        #expect(moved)
        #expect(library.groups[0].members.isEmpty)
        #expect(library.groups[1].members == [code, safari])
        // 同じグループへは移さない
        let same = library.moveMember(at: 0, from: docs, to: docs)
        #expect(!same)
        // 移す先に入っているとき
        library.addMember(code, toGroup: dev)
        let duplicate = library.moveMember(at: 0, from: docs, to: dev)
        #expect(duplicate)
        #expect(library.groups[0].members == [code])
        #expect(library.groups[1].members == [safari])
    }
}

@Suite("グループの中身の並び順")
struct GroupMemberOrderTests {
    let a = WindowSignature(bundleID: "a", title: "")
    let b = WindowSignature(bundleID: "b", title: "")
    let c = WindowSignature(bundleID: "c", title: "")

    func library() -> (StageLibrary, UUID) {
        let group = StageGroup(name: "g", members: [a, b, c], layout: .builtIn(.auto), displayID: nil)
        return (StageLibrary(groups: [group]), group.id)
    }

    @Test("入れ替える（並びの見本・2×2）")
    func swap() {
        var (library, id) = library()
        let changed = library.reorderMember(inGroup: id, from: 0, to: 2, swap: true)
        #expect(changed)
        #expect(library.groups[0].members == [c, b, a])
    }

    @Test("差し込む（横 1 列）。後ろへも前へも、指した位置に入る")
    func insert() {
        var (library, id) = library()
        library.reorderMember(inGroup: id, from: 0, to: 2, swap: false)
        #expect(library.groups[0].members == [b, c, a])
        library.reorderMember(inGroup: id, from: 2, to: 0, swap: false)
        #expect(library.groups[0].members == [a, b, c])
    }

    @Test("同じ位置・範囲の外では変えない")
    func noChange() {
        var (library, id) = library()
        let same = library.reorderMember(inGroup: id, from: 1, to: 1, swap: false)
        let outside = library.reorderMember(inGroup: id, from: 0, to: 9, swap: true)
        #expect(!same)
        #expect(!outside)
        #expect(library.groups[0].members == [a, b, c])
    }
}

@Suite("ディスプレイごとのグループ")
struct GroupsPerDisplayTests {
    let left = StageGroup(name: "左", members: [], layout: .builtIn(.auto), displayID: "LEFT")
    let right = StageGroup(name: "右", members: [], layout: .builtIn(.auto), displayID: "RIGHT")
    let any = StageGroup(name: "どこでも", members: [], layout: .builtIn(.auto), displayID: nil)
    let gone = StageGroup(name: "外したディスプレイ", members: [], layout: .builtIn(.auto), displayID: "GONE")

    var library: StageLibrary { StageLibrary(groups: [left, right, any, gone]) }

    @Test("そのディスプレイのグループと、ディスプレイを決めていないグループを並べる。並び順は全体のまま")
    func perDisplay() {
        let connected: Set<String> = ["LEFT", "RIGHT"]
        let onRight = library.groups(forDisplay: "RIGHT", connected: connected, isPrimary: false).map(\.name)
        #expect(onRight == ["右", "どこでも"])
    }

    @Test("つながっていないディスプレイのグループは、メインのディスプレイに並べる")
    func disconnected() {
        let connected: Set<String> = ["LEFT", "RIGHT"]
        let onLeft = library.groups(forDisplay: "LEFT", connected: connected, isPrimary: true).map(\.name)
        #expect(onLeft == ["左", "どこでも", "外したディスプレイ"])
    }
}

@Suite("デスクトップごとのグループ")
struct GroupsPerDesktopTests {
    let here = StageGroup(name: "ここ", members: [], layout: .builtIn(.auto), displayID: nil, desktopID: "DESK-1")
    let there = StageGroup(name: "あちら", members: [], layout: .builtIn(.auto), displayID: nil, desktopID: "DESK-2")
    let everywhere = StageGroup(name: "どこでも", members: [], layout: .builtIn(.auto), displayID: nil)
    let removed = StageGroup(name: "消したデスクトップ", members: [], layout: .builtIn(.auto), displayID: nil, desktopID: "DESK-GONE")
    let known: Set<String> = ["DESK-1", "DESK-2"]

    @Test("そのデスクトップのグループと、すべてのデスクトップのグループを出す")
    func perDesktop() {
        let shown = [here, there, everywhere].filter { $0.isShown(onDesktop: "DESK-1", knownDesktops: known) }.map(\.name)
        #expect(shown == ["ここ", "どこでも"])
    }

    @Test("覚えたデスクトップがもうないグループは、どのデスクトップにも出す（呼び出せなくならないように）")
    func removedDesktop() {
        #expect(removed.isShown(onDesktop: "DESK-1", knownDesktops: known))
        #expect(removed.isShown(onDesktop: "DESK-2", knownDesktops: known))
    }

    @Test("ウインドウバーのデスクトップが分からないときは、すべて出す")
    func unknownDesktop() {
        #expect(there.isShown(onDesktop: nil, knownDesktops: known))
    }

    @Test("前の版で保存したグループ（デスクトップを覚えていない）は、すべてのデスクトップに出す")
    func legacyFile() throws {
        let json = #"{"version":1,"groups":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"前の版","members":[],"layout":{"builtIn":{"_0":"auto"}}}],"customLayouts":[]}"#
        let library = try JSONDecoder().decode(StageLibrary.self, from: Data(json.utf8))
        #expect(library.groups.first?.desktopID == nil)
        #expect(library.groups.first?.isShown(onDesktop: "DESK-1", knownDesktops: known) == true)
    }

    @Test("出すデスクトップを変えられる。保存しても残る")
    func setDesktop() throws {
        var library = StageLibrary(groups: [everywhere])
        let changed = library.setDesktop("DESK-2", ofGroup: everywhere.id)
        #expect(changed)
        // 同じなら変えない
        let unchanged = library.setDesktop("DESK-2", ofGroup: everywhere.id)
        #expect(!unchanged)
        let decoded = try JSONDecoder().decode(StageLibrary.self, from: JSONEncoder().encode(library))
        #expect(decoded.groups.first?.desktopID == "DESK-2")
        let cleared = library.setDesktop(nil, ofGroup: everywhere.id)
        #expect(cleared)
        #expect(library.groups.first?.desktopID == nil)
    }

    @Test("グループの中身を作り直すと、出すデスクトップも、作り直したデスクトップになる")
    func contentCarriesDesktop() {
        var library = StageLibrary(groups: [everywhere])
        library.setContent(StageGroup.Content(members: [], layout: .builtIn(.auto), displayID: nil, desktopID: "DESK-1"), ofGroup: everywhere.id)
        #expect(library.groups.first?.desktopID == "DESK-1")
        let added = library.addGroup(name: nil, content: StageGroup.Content(members: [], layout: .builtIn(.auto), displayID: nil, desktopID: "DESK-2"))
        #expect(added.desktopID == "DESK-2")
    }
}

@Suite("見えている画面を記録した配置")
struct RecordedArrangementTests {
    let stage = CGRect(x: 246, y: 25, width: 1354, height: 950)

    @Test("ステージに対する割合で覚え、呼び出したときは同じ枠に戻す")
    func record() throws {
        let frames = [CGRect(x: 246, y: 25, width: 800, height: 600), CGRect(x: 700, y: 300, width: 900, height: 675)]
        let choice = LayoutChoice.recording(frames, in: stage)
        guard case .recorded(let slots) = choice else {
            Issue.record("記録した配置になっていない")
            return
        }
        let restored = slots.map { $0.rect(in: stage) }
        #expect(restored == frames)
    }

    @Test("保存して読み戻せる（前の版の保存も読める）")
    func codable() throws {
        let choice = LayoutChoice.recording([CGRect(x: 246, y: 25, width: 677, height: 475)], in: stage)
        let data = try JSONEncoder().encode(choice)
        #expect(try JSONDecoder().decode(LayoutChoice.self, from: data) == choice)
        // 前の版の保存（用意した型）も、そのまま読める
        let legacy = try JSONEncoder().encode(LayoutChoice.builtIn(.rows))
        #expect(try JSONDecoder().decode(LayoutChoice.self, from: legacy) == .builtIn(.rows))
    }

    @Test("グループの見本は、記録した枠で描く")
    func preview() {
        let slots = [UnitRect(x: 0, y: 0, width: 0.5, height: 0.5), UnitRect(x: 0.3, y: 0.3, width: 0.6, height: 0.6)]
        let preview = GroupPreview.slots(count: 2, layout: .recorded(slots), customLayouts: [])
        #expect(preview == slots)
    }

    @Test("呼び出すとき見つからなかったメンバーの枠を抜き、ほかの枠はずらさない")
    func keepingSlots() {
        let a = UnitRect(x: 0, y: 0, width: 0.5, height: 1)
        let b = UnitRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let c = UnitRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        #expect(LayoutChoice.recorded([a, b, c]).keepingSlots(where: [true, false, true]) == .recorded([a, c]))
        // ほかの並べ方は変えない
        #expect(LayoutChoice.builtIn(.rows).keepingSlots(where: [false]) == .builtIn(.rows))
    }
}
