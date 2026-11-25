import Foundation
import Testing
@testable import PinstageCore

@Suite("ウインドウ切り替え画面")
struct WindowSwitcherTests {
    @Test("初期値はデスクトップ別・一覧。グループ分けと見た目を別々に保存できる")
    func settings() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = WindowSwitcherSettings(defaults: defaults)
        #expect(settings.grouping == .byDesktop)
        #expect(settings.appearance == .list)
        settings.grouping = .flat
        settings.appearance = .icons
        settings.save(to: defaults)
        #expect(WindowSwitcherSettings(defaults: defaults) == settings)
        defaults.set("invalid", forKey: "windowSwitcher.appearance")
        #expect(WindowSwitcherSettings(defaults: defaults).grouping == .flat)
        #expect(WindowSwitcherSettings(defaults: defaults).appearance == .list)
        #expect(StripSettings(defaults: defaults) == .default)
    }

    @Test("画面収録の許可がないときはサムネイルだけを一覧に読み替える")
    func permissionFallback() {
        typealias Appearance = WindowSwitcherSettings.Appearance
        #expect(Appearance.thumbnails.displayed(hasScreenCapturePermission: false) == .list)
        #expect(Appearance.thumbnails.displayed(hasScreenCapturePermission: true) == .thumbnails)
        #expect(Appearance.icons.displayed(hasScreenCapturePermission: false) == .icons)
        #expect(Appearance.list.displayed(hasScreenCapturePermission: false) == .list)
    }

    @Test("一覧は1列、格子はパネルに収まる列数。狭いときも1列は残す")
    func tileColumns() {
        #expect(WindowSwitcherLayout.columns(for: .list, panelWidth: 560) == 1)
        #expect(WindowSwitcherLayout.columns(for: .icons, panelWidth: 600) == 8)
        #expect(WindowSwitcherLayout.columns(for: .thumbnails, panelWidth: 760) == 4)
        #expect(WindowSwitcherLayout.columns(for: .thumbnails, panelWidth: 320) == 1)
        #expect(WindowSwitcherLayout.columns(for: .icons, panelWidth: 8) == 1)
    }

    @Test("一覧を矢印キーで移動すると、空のデスクトップを飛ばす")
    func listNavigation() {
        typealias Navigation = WindowSwitcherNavigation
        let counts = [2, 0, 1]
        let top = Navigation.Position(section: 0, item: 0)
        let second = Navigation.Position(section: 0, item: 1)
        let bottom = Navigation.Position(section: 2, item: 0)
        #expect(Navigation.moving(from: top, .down, counts: counts, columns: 1) == second)
        #expect(Navigation.moving(from: second, .down, counts: counts, columns: 1) == bottom)
        #expect(Navigation.moving(from: bottom, .up, counts: counts, columns: 1) == second)
        #expect(Navigation.moving(from: bottom, .right, counts: counts, columns: 1) == bottom)
    }

    @Test("格子では上下で同じ列に移り、行にその列がなければ右端に移る")
    func gridNavigation() {
        typealias Navigation = WindowSwitcherNavigation
        let counts = [5, 0, 6]
        let row1 = Navigation.Position(section: 0, item: 1)
        let row2 = Navigation.Position(section: 0, item: 4)
        let next = Navigation.Position(section: 2, item: 1)
        #expect(Navigation.moving(from: row1, .down, counts: counts, columns: 3) == row2)
        #expect(Navigation.moving(from: row2, .up, counts: counts, columns: 3) == row1)
        #expect(Navigation.moving(from: row2, .down, counts: counts, columns: 3) == next)
        #expect(Navigation.moving(from: next, .up, counts: counts, columns: 3) == row2)
        #expect(Navigation.moving(from: .init(section: 0, item: 2), .down, counts: counts, columns: 3) == row2)
    }
}
