#if DEBUG
import AppKit
import PinstageCore
import SwiftUI

/// 開発用: 画面の見た目を、見本のデータで PNG に描き出す（アプリを起動せずに、見た目を確かめるため）
///
/// 使い方:
/// - ストリップ: Pinstage.app/Contents/MacOS/Pinstage --render-strip-preview 書き出す場所.png [見た目（medium など）] [幅] [場面]
/// - ほかの画面: Pinstage.app/Contents/MacOS/Pinstage --render-view-preview 書き出す場所.png 画面（groupEditor など）
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
    }

    /// ストリップのほかに描ける画面
    enum Screen: String {
        /// グループの編集画面
        case groupEditor
        /// 型の編集画面
        case layoutEditor
        /// 検索の欄
        case search
        /// 設定の「型」のタブ
        case layouts
    }

    /// 見本のための設定の置き場（本物の設定を読まない・書き換えない）
    private static let defaultsSuite = "app.pinstage.Pinstage.preview"

    /// 見本のデータを入れた本体
    private struct Sample {
        let stage: StageController
        let windows: [WindowItem]
        let groups: [StageGroup]
        let screen: NSScreen
    }

    static func render(to url: URL, look: StripItemSize, width: CGFloat? = nil, scenario: Scenario = .normal) {
        withSample(scenario: scenario) { sample in
            let stage = sample.stage
            stage.stripSettings.itemSize = look
            stage.stripSettings.mode = .alwaysShown
            if let width { stage.stripSettings.stripWidth = width }
            let strip = StripController(screen: sample.screen, stage: stage, thumbnails: ThumbnailStore(), shortcuts: ShortcutCenter(), actions: AppActions())
            // このストリップのデスクトップに、すべてのウインドウがあることにする
            strip.spaceState.windowIDs = Set(sample.windows.map(\.id))
            let size = CGSize(width: stage.stripSettings.effectiveWidth, height: 760)
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
        withSample(scenario: .normal, customLayouts: layouts) { sample in
            let stage = sample.stage
            switch screen {
            case .groupEditor:
                write(GroupEditorView(group: sample.groups[1], stage: stage, onSave: { _ in }, onCancel: {}), size: nil, to: url)
            case .layoutEditor:
                write(LayoutEditorView(layout: layouts[1], aspectRatio: 1.6, onSave: { _ in }, onCancel: {}), size: nil, to: url)
            case .search:
                write(SearchView(model: SearchModel(stage: stage, screen: sample.screen)), size: SearchController.size, to: url)
            case .layouts:
                let view = LayoutsSettingsView(stage: stage, editor: LayoutEditorWindowController(stage: stage))
                    .frame(width: 560, height: 360)
                write(view, size: CGSize(width: 560, height: 360), to: url)
            }
        }
    }

    /// 見本のデータを入れた本体を作って、描く（本物の設定は読まない・書き換えない）
    private static func withSample(scenario: Scenario, customLayouts: [CustomLayout] = [], _ body: (Sample) -> Void) {
        guard let screen = NSScreen.primary ?? NSScreen.screens.first,
              let defaults = UserDefaults(suiteName: defaultsSuite)
        else { return }
        defaults.removePersistentDomain(forName: defaultsSuite)
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let stage = StageController(defaults: defaults)
        let apps: [(path: String, name: String, title: String)] = [
            ("/Applications/Safari.app", "Safari", "Pinstage の README - GitHub"),
            ("/System/Applications/Mail.app", "メール", "受信 – iCloud"),
            ("/System/Library/CoreServices/Finder.app", "Finder", "ダウンロード"),
            ("/System/Applications/Notes.app", "メモ", "買い物リスト"),
            ("/System/Applications/Calendar.app", "カレンダー", "2026年11月"),
            ("/System/Applications/Utilities/Terminal.app", "ターミナル", "zsh — 80×24"),
        ]
        // 見本のウインドウ（番号の違うアプリの要素を、ウインドウの代わりに使う）
        let windows = apps.enumerated().map { index, app in
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
        let signatures = windows.compactMap(\.signature)
        let groups = [
            StageGroup(name: "開発", members: Array(signatures.prefix(2)), layout: .builtIn(.mainLeft), hasGap: false, displayID: nil),
            StageGroup(name: "資料作り", members: [signatures[2], signatures[3], signatures[4]], layout: .builtIn(.auto), hasGap: true, displayID: nil),
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
            otherDesktop: scenario == .otherDesktop ? [windows[1].id, windows[4].id] : []
        )
        body(Sample(stage: stage, windows: windows, groups: groups, screen: screen))
    }

    /// 画面の外に置いたウインドウで描いて、PNG に書き出す（size が nil なら、中身に合う大きさ）。
    /// スクロールする欄の中身も描かれるよう、実際の画面と同じ部品で描く
    private static func write(_ view: some View, size: CGSize?, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        let size = size ?? hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: size.width, height: size.height), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
