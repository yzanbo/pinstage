import CoreGraphics
import Foundation
import Testing
@testable import PinstageCore

@Suite("型の編集")
struct LayoutEditingTests {
    let rect = UnitRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)

    @Test("動かすときは目盛りに合わせ、ステージの外へ出さない")
    func move() {
        let moved = LayoutEditing.moved(rect, dx: 0.12, dy: 0, step: 0.05)
        #expect(abs(moved.x - 0.3) < 1e-9)
        let far = LayoutEditing.moved(rect, dx: 5, dy: -5, step: nil)
        #expect(far.x == 0.6)
        #expect(far.y == 0)
    }

    @Test("右下の角で大きくし、左上の角は動かさない")
    func resizeBottomRight() {
        let resized = LayoutEditing.resized(rect, corner: .bottomRight, dx: 0.1, dy: 0.1, step: nil)
        #expect(resized.x == 0.2)
        #expect(abs(resized.width - 0.5) < 1e-9)
        #expect(abs(resized.height - 0.5) < 1e-9)
    }

    @Test("左上の角で動かすと、右下の角はそのまま")
    func resizeTopLeft() {
        let resized = LayoutEditing.resized(rect, corner: .topLeft, dx: -0.1, dy: -0.1, step: nil)
        #expect(abs(resized.x - 0.1) < 1e-9)
        #expect(abs((resized.x + resized.width) - 0.6) < 1e-9)
    }

    @Test("小さくしすぎない・ステージの外へは広げない")
    func resizeLimits() {
        let tiny = LayoutEditing.resized(rect, corner: .bottomRight, dx: -1, dy: -1, step: nil)
        #expect(abs(tiny.width - LayoutEditing.minimumSize) < 1e-9)
        let huge = LayoutEditing.resized(rect, corner: .bottomRight, dx: 5, dy: 5, step: nil)
        #expect(abs((huge.x + huge.width) - 1) < 1e-9)
    }

    @Test("最前面・最背面へ移す")
    func reorder() {
        let a = UnitRect(x: 0, y: 0, width: 0.1, height: 0.1)
        let b = UnitRect(x: 0.5, y: 0, width: 0.1, height: 0.1)
        let c = UnitRect(x: 0.8, y: 0, width: 0.1, height: 0.1)
        let front = LayoutEditing.reordered([a, b, c], index: 0, toFront: true)
        #expect(front.slots == [b, c, a])
        #expect(front.index == 2)
        let back = LayoutEditing.reordered([a, b, c], index: 2, toFront: false)
        #expect(back.slots == [c, a, b])
        #expect(back.index == 0)
    }
}

@Suite("ショートカット")
struct ShortcutTests {
    @Test("初期設定はグループが ⌃⌥1〜9、ストリップが ⌃⌥S")
    func defaults() {
        let bindings = ShortcutBindings.defaults
        #expect(bindings.shortcut(for: .group1)?.displayString == "⌃⌥1")
        #expect(bindings.shortcut(for: .group9)?.displayString == "⌃⌥9")
        #expect(bindings.shortcut(for: .toggleStrip)?.displayString == "⌃⌥S")
        #expect(bindings.shortcut(for: .saveStageAsGroup) == nil)
    }

    @Test("同じキーをほかの操作に割り当てると、前の操作から外す")
    func conflict() {
        var bindings = ShortcutBindings.defaults
        let key = bindings.shortcut(for: .group1)!
        let removed = bindings.set(key, for: .saveStageAsGroup)
        #expect(removed == .group1)
        #expect(bindings.shortcut(for: .group1) == nil)
        #expect(bindings.shortcut(for: .saveStageAsGroup) == key)
    }

    @Test("外したものは、保存して読み戻しても外れたまま")
    func persistence() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ShortcutBindings(defaults: defaults) == .defaults)
        var bindings = ShortcutBindings.defaults
        bindings.set(nil, for: .group2)
        bindings.save(to: defaults)
        let loaded = ShortcutBindings(defaults: defaults)
        #expect(loaded.shortcut(for: .group2) == nil)
        #expect(loaded.shortcut(for: .group1) == bindings.shortcut(for: .group1))
    }

    @Test("⌘・⌥・⌃ のどれかがないキーは割り当てない")
    func requiredModifier() {
        #expect(!Shortcut(keyCode: 1, modifiers: ShortcutModifier.shift.carbonValue, key: "S").hasRequiredModifier)
        #expect(Shortcut(keyCode: 1, modifiers: ShortcutModifier.command.carbonValue, key: "S").hasRequiredModifier)
    }
}

@Suite("サムネイルのウインドウの照合")
struct CaptureWindowMatcherTests {
    typealias W = CaptureWindowMatcher.Window

    @Test("同じアプリで名前が同じものを選ぶ")
    func title() {
        let result = CaptureWindowMatcher.match(
            [W(pid: 1, title: "資料", frame: CGRect(x: 0, y: 0, width: 100, height: 100))],
            candidates: [
                W(pid: 1, title: "別", frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
                W(pid: 1, title: "資料", frame: CGRect(x: 300, y: 0, width: 100, height: 100)),
            ]
        )
        #expect(result == [1])
    }

    @Test("名前が分からない（空の）ときは、位置で照らし合わせる（空どうしを同じ名前とみなさない）")
    func unknownTitle() {
        let result = CaptureWindowMatcher.match(
            [W(pid: 1, title: "", frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
             W(pid: 1, title: "", frame: CGRect(x: 500, y: 0, width: 100, height: 100))],
            candidates: [W(pid: 1, title: "", frame: CGRect(x: 500, y: 0, width: 100, height: 100))]
        )
        #expect(result == [nil, 0])
    }

    @Test("名前が違っても、枠がほぼ同じなら同じウインドウ。ほかのアプリは選ばない")
    func frame() {
        let result = CaptureWindowMatcher.match(
            [W(pid: 1, title: "", frame: CGRect(x: 10, y: 10, width: 200, height: 200)),
             W(pid: 2, title: "x", frame: CGRect(x: 0, y: 0, width: 50, height: 50))],
            candidates: [
                W(pid: 1, title: "名前", frame: CGRect(x: 12, y: 10, width: 200, height: 200)),
                W(pid: 3, title: "x", frame: CGRect(x: 0, y: 0, width: 50, height: 50)),
            ]
        )
        #expect(result == [0, nil])
    }
}

@Suite("ディスプレイごとのステージ")
struct StageBoardTests {
    @Test("あるディスプレイのステージに入れると、ほかのディスプレイのステージから外れる")
    func exclusive() {
        var board = StageBoard<String>()
        board.update(on: "A") { $0.selection.replace(with: ["x", "y"]) }
        board.update(on: "B") { $0.selection.add("x") }
        #expect(board.stage(on: "A").selection.members == ["y"])
        #expect(board.stage(on: "B").selection.members == ["x"])
    }

    @Test("並べ方はディスプレイごとに持つ")
    func layoutPerDisplay() {
        var board = StageBoard<String>()
        board.update(on: "A") { $0.layout = .builtIn(.rows) }
        #expect(board.stage(on: "A").layout == .builtIn(.rows))
        #expect(board.stage(on: "B").layout == .builtIn(.auto))
    }

    @Test("閉じたウインドウは、すべてのステージから外れる")
    func prune() {
        var board = StageBoard<String>()
        board.update(on: "A") { $0.selection.replace(with: ["x"]) }
        board.update(on: "B") { $0.selection.replace(with: ["y"]) }
        board.prune(keeping: ["y"])
        #expect(board.stage(on: "A").selection.isEmpty)
        #expect(board.stage(on: "B").selection.members == ["y"])
    }
}

@Suite("グループの見本")
struct GroupPreviewTests {
    @Test("用意した型は、実際と同じ形で描く")
    func builtIn() {
        let slots = GroupPreview.slots(count: 2, layout: .builtIn(.auto), hasGap: false, customLayouts: [])
        #expect(slots == [UnitRect(x: 0, y: 0, width: 0.5, height: 1), UnitRect(x: 0.5, y: 0, width: 0.5, height: 1)])
    }

    @Test("1 枚だけのときは、真ん中に大きめに描く")
    func single() {
        let slots = GroupPreview.slots(count: 1, layout: .builtIn(.mainLeft), hasGap: false, customLayouts: [])
        #expect(slots == [GroupPreview.singleSlot])
    }

    @Test("登録した型は、その枠で描く。消した型は均等で描く")
    func custom() {
        let layout = CustomLayout(name: "マイ型", slots: [UnitRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)])
        let slots = GroupPreview.slots(count: 1, layout: .custom(layout.id), hasGap: false, customLayouts: [layout])
        #expect(slots == [UnitRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)])
        let missing = GroupPreview.slots(count: 2, layout: .custom(UUID()), hasGap: false, customLayouts: [])
        #expect(missing.count == 2)
        #expect(missing[0].width == 0.5)
    }

    @Test("間を空けると、枠が小さくなる")
    func gap() {
        let slots = GroupPreview.slots(count: 2, layout: .builtIn(.auto), hasGap: true, customLayouts: [])
        #expect(slots[0].x > 0)
        #expect(slots[0].width < 0.5)
    }
}

@Suite("順に切り替える")
struct CyclingTests {
    @Test("次・前。端まで行ったら反対の端に戻る")
    func cycle() {
        #expect(Cycling.index(after: 0, count: 3, forward: true) == 1)
        #expect(Cycling.index(after: 2, count: 3, forward: true) == 0)
        #expect(Cycling.index(after: 0, count: 3, forward: false) == 2)
    }

    @Test("まだ選んでいなければ、次は先頭、前は最後。空なら nil")
    func start() {
        #expect(Cycling.index(after: nil, count: 3, forward: true) == 0)
        #expect(Cycling.index(after: nil, count: 3, forward: false) == 2)
        #expect(Cycling.index(after: 5, count: 3, forward: true) == 0)
        #expect(Cycling.index(after: nil, count: 0, forward: true) == nil)
    }
}

@Suite("ウインドウの並び順を残す")
struct WindowOrderTests {
    let a = WindowSignature(bundleID: "a", title: "A")
    let b = WindowSignature(bundleID: "b", title: "B")
    let c = WindowSignature(bundleID: "c", title: "C")

    @Test("覚えた順に並べ直し、当てはまらないものは先頭に置く")
    func restore() {
        // いまは c, a, b の順。覚えたのは b, a の順
        let order = WindowOrderStore.restoredOrder(saved: [b, a], current: [c, a, b])
        #expect(order == [0, 2, 1])
    }

    @Test("名前が変わっていても、同じアプリのウインドウに当てはめる")
    func renamed() {
        let renamedA = WindowSignature(bundleID: "a", title: "変わった名前")
        #expect(WindowOrderStore.restoredOrder(saved: [b, a], current: [renamedA, b]) == [1, 0])
    }

    @Test("保存して読み戻せる")
    func persistence() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(WindowOrderStore.load(from: defaults).isEmpty)
        WindowOrderStore.save([a, b], to: defaults)
        #expect(WindowOrderStore.load(from: defaults) == [a, b])
    }
}

@Suite("あとから足したショートカット")
struct AddedShortcutTests {
    @Test("保存したあとに足した操作には、初期設定を入れる（外したものは外したまま）")
    func addedActions() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // 切り替える操作を足す前の保存（グループ 1 だけ外している）
        let stored: [String: Shortcut] = ["group2": ShortcutBindings.defaults.shortcut(for: .group2)!]
        defaults.set(try JSONEncoder().encode(stored), forKey: "shortcuts.bindings")
        let before: [ShortcutAction] = [.toggleStrip, .saveStageAsGroup] + ShortcutAction.groupActions
        defaults.set(before.map(\.rawValue), forKey: "shortcuts.knownActions")
        let loaded = ShortcutBindings(defaults: defaults)
        #expect(loaded.shortcut(for: .group1) == nil)
        #expect(loaded.shortcut(for: .nextGroup)?.displayString == "⌃⌥]")
        #expect(loaded.shortcut(for: .nextWindow) == nil)
        // 保存し直したあとは、外したものを外したまま読む
        var edited = loaded
        edited.set(nil, for: .nextGroup)
        edited.save(to: defaults)
        #expect(ShortcutBindings(defaults: defaults).shortcut(for: .nextGroup) == nil)
    }
}

@Suite("検索")
struct SearchMatcherTests {
    typealias Item = SearchItem<Int>
    let items: [Item] = [
        Item(id: 1, title: "開発", subtitle: "Xcode Safari"),
        Item(id: 2, title: "資料 - Safari", subtitle: "Safari"),
        Item(id: 3, title: "ダウンロード", subtitle: "ForkLift"),
        Item(id: 4, title: "safari のメモ", subtitle: "メモ"),
    ]

    @Test("何も打たなければ、渡した順のまますべて")
    func empty() {
        #expect(SearchMatcher.results(query: "  ", items: items).map(\.id) == [1, 2, 3, 4])
    }

    @Test("名前の頭に合うもの → 名前に含むもの → 添える名前に合うもの、の順")
    func ranking() {
        // 4 は名前の頭、2 は名前に含む、1 は添える名前に含む
        #expect(SearchMatcher.results(query: "safari", items: items).map(\.id) == [4, 2, 1])
    }

    @Test("空白で区切った言葉は、すべてを含むものだけ")
    func multipleTerms() {
        #expect(SearchMatcher.results(query: "safari 資料", items: items).map(\.id) == [2])
        #expect(SearchMatcher.results(query: "safari 存在しない", items: items).isEmpty)
    }

    @Test("大文字小文字・全角半角・ひらがなカタカナを区別しない")
    func normalize() {
        #expect(SearchMatcher.results(query: "ＳＡＦＡＲＩ", items: items).count == 3)
        #expect(SearchMatcher.results(query: "だうんろーど", items: items).map(\.id) == [3])
        #expect(SearchMatcher.results(query: "fork", items: items).map(\.id) == [3])
    }
}

@Suite("検索のショートカット")
struct SearchShortcutTests {
    @Test("初期設定は ⌃⌥Space")
    func defaultKey() {
        #expect(ShortcutBindings.defaults.shortcut(for: .search)?.displayString == "⌃⌥Space")
    }
}
