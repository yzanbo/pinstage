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
        #expect(DesktopWindowList<String>.puttingCurrentFirst(desktops, current: 2, id: { $0 }) == [2, 1, 3])
        #expect(DesktopWindowList<String>.puttingCurrentFirst(desktops, current: 4, id: { $0 }) == desktops)
        #expect(DesktopWindowList<String>.puttingCurrentFirst([], current: nil, id: { $0 }) == [])
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
