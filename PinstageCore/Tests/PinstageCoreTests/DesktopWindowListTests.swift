import Foundation
import Testing
@testable import PinstageCore

@Suite("デスクトップ別のウインドウ切り替え")
struct DesktopWindowListTests {
    @Test("ウインドウバーの順番を保ち、複数のデスクトップにあるものはそれぞれに入れる")
    func grouping() {
        let list = DesktopWindowList(
            windows: ["b", "all", "a", "unknown", "gone"],
            membership: ["b": [2], "all": [1, 2], "a": [1], "gone": [9]],
            desktops: [1, 2, 3]
        )
        #expect(list.byDesktop == [1: ["all", "a"], 2: ["b", "all"]])
        #expect(list.unassigned == ["unknown", "gone"])
    }

    @Test("開いたディスプレイの現在のデスクトップを先頭へ。他のデスクトップの順は変えない")
    func currentFirst() {
        let desktops: [UInt64] = [1, 2, 3]
        typealias Group = DesktopDisplayGroup<Int, UInt64>
        #expect(Group.grouping(desktops, by: { _ in 0 }, prioritizing: { $0 == 2 }).first?.items == [2, 1, 3])
        #expect(Group.grouping(desktops, by: { _ in 0 }, prioritizing: { $0 == 4 }).first?.items == desktops)
    }

    @Test("開いたディスプレイは現在と残りのデスクトップをまとめて先頭にし、残りのグループは順番を保つ")
    func displayGrouping() {
        struct Desktop {
            let id: UInt64
            let display: Int?
        }
        let desktops = [
            Desktop(id: 1, display: 1), Desktop(id: 2, display: 1),
            Desktop(id: 3, display: 2), Desktop(id: 4, display: 2), Desktop(id: 5, display: 2),
            Desktop(id: 6, display: nil),
        ]
        let groups = DesktopDisplayGroup.grouping(desktops, by: \.display, prioritizing: { $0.id == 4 })
        #expect(groups.map(\.id) == [2, 1, nil])
        #expect(groups.map { $0.items.map(\.id) } == [[4, 3, 5], [1, 2], [6]])
        let shown = groups.compactMap { $0.compactMapItems { $0.id == 3 ? $0.id : nil } }
        #expect(shown.map(\.id) == [2])
        #expect(shown.map(\.items) == [[3]])
        let barGroups = DesktopDisplayGroup.grouping(desktops, by: \.display)
        #expect(barGroups.map { $0.items.map(\.id) } == [[1, 2], [3, 4, 5], [6]])
        #expect(DesktopDisplayGroup.grouping([Desktop](), by: \.display).isEmpty)
    }

    @Test("個別ボタンの表示領域はディスプレイごとの余白を含め、幅と高さに上限を持つ")
    func buttonLayout() {
        let single = StripDesktopButtonLayout(groups: [(2, false)])
        #expect(single.rowWidth == 55)
        #expect(single.columnHeight == 51)
        #expect(!single.columnScrolls)

        let grouped = StripDesktopButtonLayout(groups: [(2, true), (1, true)])
        #expect(grouped.rowWidth == 125)
        #expect(grouped.columnHeight == 83)
        #expect(!grouped.columnScrolls)

        let overflowing = StripDesktopButtonLayout(groups: [(3, true), (3, true)])
        #expect(overflowing.rowWidth == 132)
        #expect(overflowing.columnHeight == 120)
        #expect(overflowing.columnScrolls)
    }

    @Test("デスクトップ一覧の表示は、設定を足す前のインストールでもオン。オフにした場合は保存する")
    func visibilityPreference() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("grid", forKey: "strip.itemSize")
        var settings = StripSettings(defaults: defaults)
        #expect(settings.showsDesktopList)
        settings.showsDesktopList = false
        settings.save(to: defaults)
        #expect(!StripSettings(defaults: defaults).showsDesktopList)
    }

    @Test("自動は従来どおり。まとめのみ・まとめと個別を選べば細さにかかわらずその形になる")
    func desktopButtonPresentation() {
        #expect(StripDesktopButtons.automatic.presentation(isCompact: true) == .overview)
        #expect(StripDesktopButtons.automatic.presentation(isCompact: false) == .desktopNumbers)
        for compact in [false, true] {
            #expect(StripDesktopButtons.menuOnly.presentation(isCompact: compact) == .overview)
            #expect(StripDesktopButtons.menuAndButtons.presentation(isCompact: compact) == .overviewAndDesktopNumbers)
        }
    }

    @Test("ボタンの並べ方は未設定なら自動。表示がオフでも選んだ並べ方は保持する")
    func desktopButtonPreference() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "strip.showsDesktopList")
        var settings = StripSettings(defaults: defaults)
        #expect(settings.desktopButtons == .automatic)
        settings.desktopButtons = .menuAndButtons
        settings.save(to: defaults)
        let restored = StripSettings(defaults: defaults)
        #expect(restored.desktopButtons == .menuAndButtons)
        #expect(!restored.showsDesktopList)
    }
}
