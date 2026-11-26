#if DEBUG
import AppKit
import PinstageCore
import SwiftUI

/// 開発用: 画面の見た目を、見本のデータで PNG に描き出す（アプリを起動せずに、見た目を確かめるため）
///
/// 使い方:
/// - ストリップ: Pinstage.app/Contents/MacOS/Pinstage --render-strip-preview 書き出す場所.png [見た目（grid・list・thumbnail。後ろに Small・Medium・Large を付けると大きさ。省けば小）] [幅] [場面] [辺（left・right・top・bottom）]
///   上下の辺では、幅は帯の長さ（省けば 1280）
/// - ほかの画面: Pinstage.app/Contents/MacOS/Pinstage --render-view-preview 書き出す場所.png 画面（groupEditor・general など）
enum StripPreview {
    /// ストリップを描く場面
    enum Scenario: String {
        /// ふつう（ステージに 2 枚）
        case normal
        /// アクセシビリティの許可がない
        case permission
        /// macOS のステージマネージャがオン
        case stageManager
        /// 見えている画面を記録した配置を選んでいる
        case recorded
        /// ステージが空
        case empty
        /// ほかのデスクトップのウインドウも並べている
        case otherDesktop
        /// 同じアプリのウインドウが 2 つずつある（となりに並べてつなぐ）
        case sameApp
        /// すべてのデスクトップに割り当てたウインドウがある
        case allDesktops
        /// ウインドウスイッチャーを開くボタンを出す
        case desktopList
        /// まとめボタンと各デスクトップのボタンを一緒に出す
        case desktopButtons
        /// 2 つのディスプレイの個別ボタンを、メインのバーにまとめて出す
        case desktopDisplayGroups

        var desktopPreview: StageController.PreviewDesktops {
            switch self {
            case .desktopList, .desktopButtons: .singleDisplay
            case .desktopDisplayGroups: .multipleDisplays
            default: .none
            }
        }
    }

    /// ストリップのほかに描ける画面
    enum Screen: String {
        /// グループの編集画面
        case groupEditor
        /// 型の編集画面
        case layoutEditor
        /// 検索の欄
        case search
        case desktopPicker
        case desktopOverview
        case desktopOverviewIcons
        case desktopOverviewThumbnails
        case desktopDisplayGroups
        /// 設定の「型」のタブ
        case layouts
        /// 設定の「一般」「ウインドウバー」「ショートカット」「自動化」のタブ
        case general
        case strip
        /// 設定の「ウインドウスイッチャー」のタブ
        case switcher
        case shortcuts
        case automation
    }

    /// 見本のための設定の置き場（本物の設定を読まない・書き換えない）
    private static let defaultsSuite = "app.pinstage.Pinstage.preview"

    /// 見本のデータを入れた本体（README の画像を作るときにも使う）
    struct Sample {
        let stage: StageController
        let windows: [WindowItem]
        let groups: [StageGroup]
        let screen: NSScreen
    }

    /// ストリップの見た目（形式と大きさ）。「list」「gridLarge」「thumbnailMedium」のように、形式の後ろに大きさ（Small・Medium・Large）を付ける。
    /// 大きさを省けば「小」（初期設定）
    struct Look {
        let format: StripItemSize
        let iconSize: StripIconSize

        init(format: StripItemSize, iconSize: StripIconSize = .small) {
            self.format = format
            self.iconSize = iconSize
        }

        init?(rawValue: String) {
            guard let format = StripItemSize.allCases.first(where: { rawValue.hasPrefix($0.rawValue) }) else { return nil }
            let suffix = rawValue.dropFirst(format.rawValue.count).lowercased()
            if suffix.isEmpty {
                self.init(format: format)
            } else if let size = StripIconSize(rawValue: suffix) {
                self.init(format: format, iconSize: size)
            } else {
                return nil
            }
        }

        static let list = Look(format: .list)
    }

    static func render(to url: URL, look: Look, width: CGFloat? = nil, scenario: Scenario = .normal, edge: StripEdge = .left) {
        withSample(scenario: scenario) { sample in
            let stage = sample.stage
            stage.stripSettings.itemSize = look.format
            stage.stripSettings.iconSize = look.iconSize
            stage.stripSettings.mode = .alwaysShown
            stage.stripSettings.edge = edge
            // いまの形式の幅として入れる（範囲の中に収まる。アイコンの並びは、1 列になる幅まで狭められる）
            if let width, !edge.isHorizontal { stage.stripSettings.width = width }
            let strip = StripController(screen: sample.screen, stage: stage, thumbnails: ThumbnailStore(), shortcuts: ShortcutCenter(), actions: AppActions())
            // このストリップのデスクトップに、すべてのウインドウがあることにする
            strip.spaceState.windowIDs = Set(sample.windows.map(\.id))
            let thickness = stage.stripSettings.effectiveThickness
            let size = edge.isHorizontal
                ? CGSize(width: width ?? 1280, height: thickness)
                : CGSize(width: thickness, height: 760)
            let view = StripView(stage: stage, thumbnails: ThumbnailStore(), shortcuts: ShortcutCenter(), strip: strip, actions: AppActions())
                .frame(width: size.width, height: size.height)
                .background(Color(white: 0.45))
            write(view, size: size, to: url)
        }
    }

    static func render(_ screen: Screen, to url: URL) {
        // 登録した型も 2 つ入れておく（型の一覧・グループの編集画面の並べ方の欄に出る）
        let layouts = [
            CustomLayout(name: "左右", slots: [UnitRect(x: 0, y: 0, width: 0.4, height: 1), UnitRect(x: 0.4, y: 0, width: 0.6, height: 1)]),
            CustomLayout(name: "重ねた形", slots: [UnitRect(x: 0, y: 0, width: 0.6, height: 0.7), UnitRect(x: 0.3, y: 0.25, width: 0.7, height: 0.75), UnitRect(x: 0.1, y: 0.5, width: 0.4, height: 0.4)]),
        ]
        let isDesktopPicker = [Screen.desktopPicker, .desktopOverview, .desktopOverviewIcons, .desktopOverviewThumbnails].contains(screen)
        let scenario: Scenario = screen == .desktopDisplayGroups ? .desktopDisplayGroups : isDesktopPicker ? .desktopList : .normal
        withSample(scenario: scenario, customLayouts: layouts) { sample in
            let stage = sample.stage
            switch screen {
            case .groupEditor:
                write(GroupEditorView(group: sample.groups[1], stage: stage, onSave: { _ in }, onCancel: {}), size: nil, to: url)
            case .layoutEditor:
                write(LayoutEditorView(layout: layouts[1], aspectRatio: 1.6, onSave: { _ in }, onCancel: {}), size: nil, to: url)
            case .search:
                write(SearchView(model: SearchModel(stage: stage, screen: sample.screen)), size: SearchController.size, to: url)
            case .desktopPicker, .desktopOverview, .desktopOverviewIcons, .desktopOverviewThumbnails, .desktopDisplayGroups:
                let anchored = screen == .desktopPicker
                let appearance: WindowSwitcherSettings.Appearance = switch screen {
                case .desktopOverviewIcons, .desktopDisplayGroups: .icons
                case .desktopOverviewThumbnails: .thumbnails
                // ウインドウバーのボタンから開いたときは、初期設定の見た目（アイコンだけ）
                case .desktopPicker: .icons
                default: .list
                }
                if screen == .desktopOverviewIcons { stage.windowSwitcherSettings.grouping = .flat }
                // 画面の上の切り替えに、描いている見た目が選ばれているように
                stage.windowSwitcherSettings.appearance = appearance
                // ウインドウバーのボタン（デスクトップ 2）から開いたときは、そのデスクトップの最初のウインドウを選んで開く
                let preview = DesktopPickerController.preview(stage: stage, screen: sample.screen, focusing: anchored ? 2 : nil,
                                                              appearance: appearance)
                write(preview.view, size: preview.size, to: url)
            case .layouts:
                let view = LayoutsSettingsView(stage: stage, editor: LayoutEditorWindowController(stage: stage))
                    .frame(width: 560, height: 360)
                write(view, size: CGSize(width: 560, height: 360), to: url)
            case .general:
                write(GeneralSettingsView(stage: stage, thumbnails: ThumbnailStore(), launchAtLogin: LaunchAtLogin()), size: nil, to: url)
            case .strip:
                write(StripSettingsView(stage: stage, thumbnails: ThumbnailStore()), size: nil, to: url)
            case .switcher:
                let shortcuts = ShortcutCenter()
                write(SwitcherSettingsView(stage: stage, thumbnails: ThumbnailStore(), shortcuts: shortcuts,
                                           recorder: ShortcutRecorderModel(shortcuts: shortcuts)), size: nil, to: url)
            case .shortcuts:
                let shortcuts = ShortcutCenter()
                write(ShortcutSettingsView(shortcuts: shortcuts, recorder: ShortcutRecorderModel(shortcuts: shortcuts), stage: stage), size: nil, to: url)
            case .automation:
                write(AutomationSettingsView(stage: stage), size: nil, to: url)
            }
        }
    }

    /// 見本のデータを入れた本体を作って、描く（本物の設定は読まない・書き換えない）
    static func withSample(scenario: Scenario, customLayouts: [CustomLayout] = [], _ body: (Sample) -> Void) {
        guard let screen = NSScreen.primary ?? NSScreen.screens.first,
              let defaults = UserDefaults(suiteName: defaultsSuite)
        else { return }
        defaults.removePersistentDomain(forName: defaultsSuite)
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let stage = StageController(defaults: defaults)
        if scenario == .desktopButtons || scenario == .desktopDisplayGroups {
            stage.stripSettings.desktopButtons = .menuAndButtons
        }
        if scenario.desktopPreview == .multipleDisplays { stage.stripSettings.displays = .mainOnly }
        let apps: [(path: String, name: String, title: String)] = [
            ("/Applications/Safari.app", "Safari", "Pinstage の README - GitHub"),
            ("/System/Applications/Mail.app", "メール", "受信 – iCloud"),
            ("/System/Library/CoreServices/Finder.app", "Finder", "ダウンロード"),
            ("/System/Applications/Notes.app", "メモ", "買い物リスト"),
            ("/System/Applications/Calendar.app", "カレンダー", "2026年11月"),
            ("/System/Applications/Utilities/Terminal.app", "ターミナル", "zsh — 80×24"),
        ] + (scenario == .sameApp ? [
            ("/Applications/Safari.app", "Safari", "Apple（日本）"),
            ("/System/Applications/Utilities/Terminal.app", "ターミナル", "make run"),
        ] : [])
        // 見本のウインドウ（番号の違うアプリの要素を、ウインドウの代わりに使う）
        let created = apps.enumerated().map { index, app in
            WindowItem(
                id: AXUIElementCreateApplication(pid_t(90_000 + index)),
                pid: pid_t(90_000 + index),
                bundleID: Bundle(path: app.path)?.bundleIdentifier,
                appName: app.name,
                title: app.title,
                icon: NSWorkspace.shared.icon(forFile: app.path),
                isMinimized: index == 3
            )
        }
        // 後から開いたウインドウ（同じアプリの 2 つ目）は、本物と同じく、同じアプリのウインドウのすぐ後ろに入れる
        let byID = Dictionary(created.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let windows = RecentOrder.appending(created.dropFirst(6).map(\.id), to: created.prefix(6).map(\.id)) { byID[$0]?.appKey }
            .compactMap { byID[$0] }
        let signatures = windows.compactMap(\.signature)
        let groups = [
            StageGroup(name: "開発", members: Array(signatures.prefix(2)), layout: .builtIn(.mainLeft), displayID: nil),
            StageGroup(name: "資料作り", members: [signatures[2], signatures[3], signatures[4]], layout: .builtIn(.auto), displayID: nil),
        ]
        stage.loadPreview(
            windows: windows,
            groups: groups,
            onStage: scenario == .empty ? [] : [windows[0].id, windows[2].id],
            screen: screen,
            isTrusted: scenario != .permission,
            isSystemStageManagerOn: scenario == .stageManager,
            layout: scenario == .recorded
                ? .recorded([UnitRect(x: 0, y: 0, width: 0.6, height: 0.7), UnitRect(x: 0.3, y: 0.25, width: 0.7, height: 0.75)])
                : nil,
            customLayouts: customLayouts,
            otherDesktop: scenario == .otherDesktop ? [windows[1].id, windows[4].id] : [],
            allDesktops: scenario == .allDesktops ? [windows[1].id, windows[5].id] : [],
            desktopPreview: scenario.desktopPreview,
            // Dock のバッジ（メールは数、メモは点）。デスクトップの一覧の見本で見る
            badges: scenario == .desktopList || scenario == .allDesktops ? ["com.apple.mail": "3", "com.apple.Notes": "•"] : [:]
        )
        body(Sample(stage: stage, windows: windows, groups: groups, screen: screen))
    }

    /// 画面の外に置いたウインドウで描いて、PNG に書き出す（size が nil なら、中身に合う大きさ）
    private static func write(_ view: some View, size: CGSize?, to url: URL) {
        try? snapshot(view, size: size)?.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// 画面の外に置いたウインドウで描き写す（size が nil なら、中身に合う大きさ。画素は画面の倍率）。
    /// スクロールする欄の中身も描かれるよう、実際の画面と同じ部品で描く。transparent なら、ウインドウの地を描かない（ほかの絵に重ねるとき）
    static func snapshot(_ view: some View, size: CGSize?, appearance: NSAppearance.Name = .darkAqua, transparent: Bool = false) -> NSBitmapImageRep? {
        let hosting = NSHostingView(rootView: view)
        let size = size ?? hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: size.width, height: size.height), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        if transparent {
            window.isOpaque = false
            window.backgroundColor = .clear
        }
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        defer { window.orderOut(nil) }
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }
}
#endif
