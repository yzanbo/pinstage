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
            hasGap: true,
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
        let stage = StripGeometry.stageFrame(in: visible, mode: .alwaysShown)
        let strip = StripGeometry.shownFrame(in: visible)
        #expect(stage.minX == strip.maxX + StripGeometry.margin)
        #expect(stage.maxX == visible.maxX)
    }

    @Test("ストリップは、ステージと同じく上下いっぱいを使う")
    func fullHeight() {
        let strip = StripGeometry.shownFrame(in: visible)
        let stage = StripGeometry.stageFrame(in: visible, mode: .alwaysShown)
        #expect(strip.minY == visible.minY)
        #expect(strip.maxY == visible.maxY)
        #expect(strip.minY == stage.minY && strip.maxY == stage.maxY)
    }

    @Test("自動で隠すときは、画面いっぱいをステージにする")
    func stageAutoHide() {
        #expect(StripGeometry.stageFrame(in: visible, mode: .autoHide) == visible)
    }

    @Test("左端にポインタが来たら出し、離れたら隠す")
    func revealAndHide() {
        #expect(StripGeometry.shouldReveal(pointer: CGPoint(x: 1, y: 500), screenFrame: visible))
        #expect(!StripGeometry.shouldReveal(pointer: CGPoint(x: 50, y: 500), screenFrame: visible))
        // 左隣のディスプレイの上では出さない
        let right = CGRect(x: 1600, y: 0, width: 1600, height: 1000)
        #expect(!StripGeometry.shouldReveal(pointer: CGPoint(x: 800, y: 500), screenFrame: right))
        #expect(StripGeometry.shouldReveal(pointer: CGPoint(x: 1601, y: 500), screenFrame: right))
        let strip = StripGeometry.shownFrame(in: visible)
        #expect(!StripGeometry.shouldHide(pointer: CGPoint(x: strip.maxX + 10, y: 500), stripFrame: strip))
        #expect(StripGeometry.shouldHide(pointer: CGPoint(x: strip.maxX + 100, y: 500), stripFrame: strip))
    }

    @Test("幅を変えると、ストリップとステージの境目も動く")
    func width() {
        let strip = StripGeometry.shownFrame(in: visible, width: 320)
        let stage = StripGeometry.stageFrame(in: visible, mode: .alwaysShown, width: 320)
        #expect(strip.width == 320)
        #expect(stage.minX == strip.maxX + StripGeometry.margin)
        #expect(StripGeometry.hiddenFrame(in: visible, width: 320).maxX < visible.minX)
    }

    @Test("ドラッグの幅は範囲の中に収め、画面の半分より広くしない")
    func dragWidth() {
        #expect(StripGeometry.width(forPointerX: 300, in: visible) == 300 - StripGeometry.margin)
        #expect(StripGeometry.width(forPointerX: 20, in: visible) == StripGeometry.widthRange.lowerBound)
        #expect(StripGeometry.width(forPointerX: 2000, in: visible) == StripGeometry.widthRange.upperBound)
        let narrow = CGRect(x: 0, y: 0, width: 600, height: 800)
        #expect(StripGeometry.width(forPointerX: 500, in: narrow) == 300)
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

    @Test("アイコンだけのときは細い幅に決め、変えた幅は覚えておく")
    func iconOnlyWidth() {
        var settings = StripSettings.default
        settings.stripWidth = 320
        settings.itemSize = .icons
        #expect(settings.effectiveWidth == StripGeometry.iconOnlyWidth)
        #expect(!settings.itemSize.showsAppName)
        #expect(settings.itemSize.thumbnailHeight == 0)
        settings.itemSize = .list
        #expect(settings.effectiveWidth == 320)
    }

    @Test("並べる数は範囲の中に収める")
    func visibleCount() {
        #expect(StripSettings(mode: .autoHide, itemSize: .list, visibleCount: 0, displays: .all).visibleCount == 3)
        #expect(StripSettings(mode: .autoHide, itemSize: .list, visibleCount: 99, displays: .all).visibleCount == 30)
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

@Suite("グループのアプリを終了")
struct GroupQuitTests {
    @Test("同じアプリは 1 回だけ、Finder は終了しない")
    func bundleIDs() {
        let group = StageGroup(
            name: "開発",
            members: [
                WindowSignature(bundleID: "com.apple.Safari", title: "a"),
                WindowSignature(bundleID: "com.apple.finder", title: "b"),
                WindowSignature(bundleID: "com.apple.Safari", title: "c"),
                WindowSignature(bundleID: "com.microsoft.VSCode", title: "d"),
            ],
            layout: .builtIn(.auto),
            hasGap: false,
            displayID: nil
        )
        #expect(group.bundleIDsToQuit == ["com.apple.Safari", "com.microsoft.VSCode"])
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
    let dev = StageGroup(name: "開発", members: [], layout: .builtIn(.auto), hasGap: false, displayID: nil)
    let docs = StageGroup(name: "Docs", members: [], layout: .builtIn(.auto), hasGap: false, displayID: nil)

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
        let dev = StageGroup(name: "開発", members: [safari], layout: .builtIn(.auto), hasGap: false, displayID: nil)
        let docs = StageGroup(name: "資料", members: [code], layout: .builtIn(.auto), hasGap: false, displayID: nil)
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
        let group = StageGroup(name: "g", members: [a, b, c], layout: .builtIn(.auto), hasGap: false, displayID: nil)
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
    let left = StageGroup(name: "左", members: [], layout: .builtIn(.auto), hasGap: false, displayID: "LEFT")
    let right = StageGroup(name: "右", members: [], layout: .builtIn(.auto), hasGap: false, displayID: "RIGHT")
    let any = StageGroup(name: "どこでも", members: [], layout: .builtIn(.auto), hasGap: false, displayID: nil)
    let gone = StageGroup(name: "外したディスプレイ", members: [], layout: .builtIn(.auto), hasGap: false, displayID: "GONE")

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
        #expect(choice.hasOwnSpacing)
        #expect(!LayoutChoice.builtIn(.auto).hasOwnSpacing)
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
        let preview = GroupPreview.slots(count: 2, layout: .recorded(slots), hasGap: false, customLayouts: [])
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
