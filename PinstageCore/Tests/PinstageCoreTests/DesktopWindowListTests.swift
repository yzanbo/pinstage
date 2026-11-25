import CoreGraphics
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

    @Test("どの辺でも画面の内側へ開き、端に寄ったボタンの一覧も画面からはみ出さない")
    func anchoredGeometry() {
        let visible = CGRect(x: -800, y: 100, width: 800, height: 600)
        let size = CGSize(width: 320, height: 440)
        for edge in StripEdge.allCases {
            let bar = StripGeometry.shownFrame(in: visible, edge: edge, thickness: 100)
            let anchor = CGRect(x: bar.minX + 2, y: bar.maxY - 24, width: 22, height: 22)
            let frame = DesktopListGeometry.panel(size: size, in: visible, anchor: anchor, bar: bar, edge: edge)
            #expect(visible.contains(frame))
            #expect(!bar.intersects(frame))
            switch edge {
            case .left: #expect(frame.minX - bar.maxX == 6)
            case .right: #expect(bar.minX - frame.maxX == 6)
            case .top: #expect(bar.minY - frame.maxY == 6)
            case .bottom: #expect(frame.minY - bar.maxY == 6)
            }
        }
    }

    @Test("ショートカットから開く一覧は画面中央に収める")
    func centeredGeometry() {
        let visible = CGRect(x: 120, y: 60, width: 500, height: 360)
        let frame = DesktopListGeometry.panel(size: CGSize(width: 560, height: 280), in: visible)
        #expect(frame == CGRect(x: 120, y: 100, width: 500, height: 280))
    }
}
