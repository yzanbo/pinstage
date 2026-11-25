import Foundation
import Testing
@testable import PinstageCore

@Suite("ウインドウスイッチャー")
struct WindowSwitcherTests {
    @Test("初期値はデスクトップ別・アイコンだけ・中。グループ分け・見た目・大きさを別々に保存する")
    func settings() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = WindowSwitcherSettings(defaults: defaults)
        #expect(settings.grouping == .byDesktop)
        #expect(settings.appearance == .icons)
        #expect(settings.displaySize == .medium)
        settings.grouping = .flat
        settings.appearance = .list
        settings.displaySize = .large
        settings.save(to: defaults)
        #expect(WindowSwitcherSettings(defaults: defaults) == settings)
        defaults.set("invalid", forKey: "windowSwitcher.appearance")
        #expect(WindowSwitcherSettings(defaults: defaults).grouping == .flat)
        #expect(WindowSwitcherSettings(defaults: defaults).appearance == .icons)
        #expect(WindowSwitcherSettings(defaults: defaults).displaySize == .large)
        defaults.set("invalid", forKey: "windowSwitcher.displaySize")
        #expect(WindowSwitcherSettings(defaults: defaults).displaySize == .medium)
        #expect(StripSettings(defaults: defaults) == .default)
    }

    @Test("確定方法は従来どおりキーを離すのが初期値。見た目とは別に保存する")
    func confirmationSettings() throws {
        let suite = "PinstageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(WindowSwitcherSettings().confirmation == .onModifierRelease)
        var settings = WindowSwitcherSettings(defaults: defaults)
        #expect(settings.confirmation == .onModifierRelease)
        settings.confirmation = .explicit
        settings.save(to: defaults)
        #expect(WindowSwitcherSettings(defaults: defaults) == settings)
        defaults.set("invalid", forKey: "windowSwitcher.confirmation")
        #expect(WindowSwitcherSettings(defaults: defaults) == WindowSwitcherSettings())
    }

    private struct Modifiers: OptionSet {
        let rawValue: Int
        static let option = Self(rawValue: 1)
        static let command = Self(rawValue: 2)
        static let shift = Self(rawValue: 4)
    }

    @Test("登録された修飾キーをすべて離したときに一度だけ確定する")
    func releaseConfirmsOnce() {
        var release = WindowSwitcherRelease<Modifiers>(confirmation: .onModifierRelease, shortcutModifiers: [.option, .command])
        #expect(release.isWaiting)
        let releasedOneKey = release.consumeIfReleased([.option])
        #expect(!releasedOneKey)
        let releasedBothKeys = release.consumeIfReleased([.shift])
        #expect(releasedBothKeys)
        #expect(!release.isWaiting)
        let confirmedAgain = release.consumeIfReleased([])
        #expect(!confirmedAgain)
    }

    @Test("Enter・ボタンで開いた場合や、待機を取り消した場合は自動確定しない")
    func releaseDoesNotConfirm() {
        var explicit = WindowSwitcherRelease<Modifiers>(confirmation: .explicit, shortcutModifiers: [.option])
        var fromButton = WindowSwitcherRelease<Modifiers>(confirmation: .onModifierRelease, shortcutModifiers: nil)
        var cancelled = WindowSwitcherRelease<Modifiers>(confirmation: .onModifierRelease, shortcutModifiers: [.option])
        cancelled.cancel()
        let explicitConfirmed = explicit.consumeIfReleased([])
        let fromButtonConfirmed = fromButton.consumeIfReleased([])
        let cancelledConfirmed = cancelled.consumeIfReleased([])
        #expect(!explicitConfirmed)
        #expect(!fromButtonConfirmed)
        #expect(!cancelledConfirmed)
    }

    @Test("切り替え画面の中では、⌘G でグループ分けを入れ替え、⌘1〜3 で見た目を選ぶ")
    func inPanelShortcuts() {
        typealias Appearance = WindowSwitcherSettings.Appearance
        #expect(WindowSwitcherSettings.Grouping.byDesktop.toggled == .flat)
        #expect(WindowSwitcherSettings.Grouping.flat.toggled == .byDesktop)
        #expect(Appearance(shortcutNumber: 1) == .list)
        #expect(Appearance(shortcutNumber: 2) == .icons)
        #expect(Appearance(shortcutNumber: 3) == .thumbnails)
        #expect(Appearance(shortcutNumber: 0) == nil)
        #expect(Appearance(shortcutNumber: 4) == nil)
    }

    @Test("画面収録の許可がないときはサムネイルだけをアイコンだけに読み替える")
    func permissionFallback() {
        typealias Appearance = WindowSwitcherSettings.Appearance
        #expect(Appearance.thumbnails.displayed(hasScreenCapturePermission: false) == .icons)
        #expect(Appearance.thumbnails.displayed(hasScreenCapturePermission: true) == .thumbnails)
        #expect(Appearance.icons.displayed(hasScreenCapturePermission: false) == .icons)
        #expect(Appearance.list.displayed(hasScreenCapturePermission: false) == .list)
    }

    @Test("画面の高さは中身に合わせる。少ないときはいちばん低い高さ、多いときは上限で止める（スクロール）")
    func overviewHeight() {
        typealias Layout = WindowSwitcherLayout
        // アイコンだけ・デスクトップ 3 つ（3・3・0 個）・8 列 → 各デスクトップ 1 行
        let icons = Layout.overviewHeight(for: .icons, sectionCounts: [3, 3, 0], titledSections: true, columns: 8, maximumHeight: 900)
        let sections: CGFloat = 3 * (Layout.sectionTitleHeight + Layout.sectionTitleSpacing) + 2 * Layout.sectionSpacing
        let bodies: CGFloat = 2 * Layout.tileHeight(for: .icons) + Layout.emptySectionHeight
        let chrome: CGFloat = Layout.inset * 2 + Layout.headerHeight + Layout.blockSpacing
            + Layout.blockSpacing + Layout.footerHeight + Layout.blockSpacing + Layout.hintsHeight
        #expect(icons == (sections + bodies + chrome).rounded(.up))
        // ウインドウが 1 つでも、いちばん低い高さより低くしない
        #expect(Layout.overviewHeight(for: .list, sectionCounts: [1], titledSections: false, columns: 1, maximumHeight: 900) == Layout.minimumOverviewHeight)
        // 多いときは上限で止める
        #expect(Layout.overviewHeight(for: .list, sectionCounts: [40], titledSections: false, columns: 1, maximumHeight: 700) == 700)
        // 格子は、列の数で行の数が決まる（9 個・8 列 → 2 行）
        let oneRow = Layout.overviewHeight(for: .icons, sectionCounts: [8, 1], titledSections: true, columns: 8, maximumHeight: 900)
        let twoRows = Layout.overviewHeight(for: .icons, sectionCounts: [9, 1], titledSections: true, columns: 8, maximumHeight: 900)
        #expect(twoRows - oneRow == Layout.tileHeight(for: .icons) + Layout.tileSpacing)
    }

    @Test("画面の幅は、見た目ごとのちょうどよい幅。画面が狭ければ、画面の割合で止める")
    func overviewWidth() {
        typealias Layout = WindowSwitcherLayout
        #expect(Layout.overviewWidth(for: .icons, visibleWidth: 1800) == Layout.preferredWidth(for: .icons))
        #expect(Layout.overviewWidth(for: .thumbnails, visibleWidth: 1000) == 720)
    }

    @Test("一覧は1列、格子はパネルに収まる列数。狭いときも1列は残す")
    func tileColumns() {
        #expect(WindowSwitcherLayout.columns(for: .list, panelWidth: 760) == 1)
        // (1040 - 32 + 10) ÷ (110 + 10) ≒ 8.5 → 8 列
        #expect(WindowSwitcherLayout.columns(for: .icons, panelWidth: 1040) == 8)
        // (1240 - 32 + 10) ÷ (250 + 10) ≒ 4.7 → 4 列
        #expect(WindowSwitcherLayout.columns(for: .thumbnails, panelWidth: 1240) == 4)
        #expect(WindowSwitcherLayout.columns(for: .thumbnails, panelWidth: 320) == 1)
        #expect(WindowSwitcherLayout.columns(for: .icons, panelWidth: 8) == 1)
    }

    @Test("パネルは対象のディスプレイの中央に収まり、負の座標や表示領域より大きい寸法も扱う")
    func centeredPanel() {
        let visible = CGRect(x: -500, y: 60, width: 500, height: 360)
        #expect(WindowSwitcherLayout.panelFrame(size: CGSize(width: 560, height: 280), in: visible)
            == CGRect(x: -500, y: 100, width: 500, height: 280))
        #expect(WindowSwitcherLayout.panelFrame(size: CGSize(width: 320, height: 420), in: visible)
            == CGRect(x: -410, y: 60, width: 320, height: 360))
    }

    @Test("ディスプレイの枠と見出しを含めて高さと列数を決める")
    func displayGroupLayout() {
        typealias Layout = WindowSwitcherLayout
        #expect(Layout.columns(for: .icons, panelWidth: 520) == 4)
        #expect(Layout.columns(for: .icons, panelWidth: 520, showsDisplayGroups: true) == 3)
        let plain = Layout.overviewHeight(for: .list, sectionCounts: [2, 2], titledSections: true, columns: 1, maximumHeight: 800)
        let grouped = Layout.overviewHeight(
            for: .list, sectionCounts: [2, 2], titledSections: true, columns: 1, maximumHeight: 800, displayGroupCount: 2
        )
        #expect(grouped - plain == 2 * (2 * Layout.displayGroupInset + Layout.displayTitleHeight + Layout.displayTitleSpacing))
    }

    @Test("大きさは一覧の行・格子のアイコン・サムネイルに反映され、中は従来の寸法")
    func displaySizes() {
        typealias Layout = WindowSwitcherLayout
        #expect(Layout.iconSize(for: .medium) == 64)
        #expect(Layout.thumbnailImageHeight(for: .medium) == 150)
        #expect(Layout.listRowHeight(for: .medium) == 46)
        for appearance in WindowSwitcherSettings.Appearance.allCases {
            #expect(Layout.tileHeight(for: appearance, size: .small) < Layout.tileHeight(for: appearance, size: .medium))
            #expect(Layout.tileHeight(for: appearance, size: .medium) < Layout.tileHeight(for: appearance, size: .large))
        }
        for appearance in [WindowSwitcherSettings.Appearance.icons, .thumbnails] {
            #expect(Layout.columns(for: appearance, size: .small, panelWidth: 1040) > Layout.columns(for: appearance, size: .large, panelWidth: 1040))
            #expect(Layout.columns(for: appearance, size: .large, panelWidth: 64) == 1)
        }
        let small = Layout.overviewHeight(for: .list, size: .small, sectionCounts: [8], titledSections: false, columns: 1, maximumHeight: 800)
        let large = Layout.overviewHeight(for: .list, size: .large, sectionCounts: [8], titledSections: false, columns: 1, maximumHeight: 800)
        #expect(large - small == 8 * (Layout.listRowHeight(for: .large) - Layout.listRowHeight(for: .small)))
        #expect(Layout.overviewHeight(for: .list, size: .large, sectionCounts: [20], titledSections: false, columns: 1, maximumHeight: 400) == 400)
    }

    @Test("文字を打って絞り込む（ウインドウ名かアプリ名。かな・英大小・全角半角はそろえる）")
    func filter() {
        #expect(WindowSwitcherFilter(query: "").matches(title: "受信", appName: "メール"))
        #expect(WindowSwitcherFilter(query: "sl").matches(title: "general", appName: "Slack"))
        #expect(WindowSwitcherFilter(query: "ＳＬ").matches(title: "general", appName: "Slack"))
        #expect(WindowSwitcherFilter(query: "めーる").matches(title: "受信", appName: "メール"))
        #expect(!WindowSwitcherFilter(query: "line").matches(title: "受信", appName: "メール"))
        // 空白で区切った言葉は、すべてを含むもの
        #expect(WindowSwitcherFilter(query: "sl gen").matches(title: "general", appName: "Slack"))
        #expect(!WindowSwitcherFilter(query: "sl x").matches(title: "general", appName: "Slack"))
    }

    @Test("Tab で順に進み、最後の次は最初へ。⇧Tab で戻り、最初の前は最後へ（空のデスクトップは飛ばす）")
    func tabStepping() {
        typealias Navigation = WindowSwitcherNavigation
        let counts = [2, 0, 1]
        let p = { (section: Int, item: Int) in Navigation.Position(section: section, item: item) }
        #expect(Navigation.stepping(from: p(0, 0), forward: true, counts: counts) == p(0, 1))
        #expect(Navigation.stepping(from: p(0, 1), forward: true, counts: counts) == p(2, 0))
        #expect(Navigation.stepping(from: p(2, 0), forward: true, counts: counts) == p(0, 0))
        #expect(Navigation.stepping(from: p(0, 0), forward: false, counts: counts) == p(2, 0))
        #expect(Navigation.stepping(from: nil, forward: true, counts: counts) == p(0, 0))
        #expect(Navigation.stepping(from: nil, forward: true, counts: [0, 0]) == nil)
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
