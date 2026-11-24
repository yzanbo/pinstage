import AppKit
import PinstageCore
import SwiftUI

/// 設定のタブ
enum SettingsTab: Int {
    case general
    case layouts
    case shortcuts
    case automation
}

/// 設定のウインドウ。macOS の設定画面と同じく、上のツールバーのタブで項目を分ける（Pinshelf と同じ作り）
///
/// メニューバー常駐のアプリでは SwiftUI の Settings が後ろに隠れることがあるので、自前のウインドウで開き、前面に出す。
final class SettingsWindowController {
    private let stage: StageController
    private let thumbnails: ThumbnailStore
    private let shortcuts: ShortcutCenter
    private let editor: LayoutEditorWindowController
    private let launchAtLogin = LaunchAtLogin()
    private lazy var recorder = ShortcutRecorderModel(shortcuts: shortcuts)
    private var window: NSWindow?
    private var tabs: NSTabViewController?
    private var closeObserver: NSObjectProtocol?

    init(stage: StageController, thumbnails: ThumbnailStore, shortcuts: ShortcutCenter, editor: LayoutEditorWindowController) {
        self.stage = stage
        self.thumbnails = thumbnails
        self.shortcuts = shortcuts
        self.editor = editor
    }

    func show(tab: SettingsTab? = nil) {
        let window = self.window ?? makeWindow()
        self.window = window
        if let tab { tabs?.selectedTabViewItemIndex = tab.rawValue }
        // 開いている間は Dock にアイコンを出す（Dock と ⌘Tab から戻れるように。閉じたら消える）
        DockIcon.present(window)
    }

    private func makeWindow() -> NSWindow {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(makeTab("一般", symbol: "gearshape", view: GeneralSettingsView(stage: stage, thumbnails: thumbnails, launchAtLogin: launchAtLogin)))
        tabs.addTabViewItem(makeTab("型", symbol: "rectangle.split.3x1", view: LayoutsSettingsView(stage: stage, editor: editor)))
        tabs.addTabViewItem(makeTab("ショートカット", symbol: "command", view: ShortcutSettingsView(shortcuts: shortcuts, recorder: recorder)))
        tabs.addTabViewItem(makeTab("自動化", symbol: "gearshape.2", view: AutomationSettingsView(stage: stage)))
        self.tabs = tabs

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        // 最初のタブの名前を、ウインドウの名前にする（何もしないと「Untitled」になる）
        window.title = tabs.tabViewItems.first?.label ?? "設定"
        window.isReleasedWhenClosed = false
        window.center()
        recorder.window = window
        // ショートカットを記録したまま閉じたら、記録をやめる（記録している間は、すべてのショートカットを止めているため）
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recorder.stop() }
        }
        return window
    }

    private func makeTab<Content: View>(_ label: String, symbol: String, view: Content) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view)
        controller.title = label
        // タブごとの中身の大きさに合わせて、ウインドウの大きさを変える
        controller.sizingOptions = [.preferredContentSize]
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

/// 設定のタブ。選んだタブの名前を、ウインドウの名前にする（macOS の設定画面と同じ）
private final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let label = tabViewItem?.label {
            view.window?.title = label
        }
    }
}

extension StripMode: SettingsOption {}
extension StripEdge: SettingsOption {}
extension StripItemSize: SettingsOption {}
extension StripIconSize: SettingsOption {}
extension StripDisplays: SettingsOption {}
extension SingleWindowSize: SettingsOption {}
