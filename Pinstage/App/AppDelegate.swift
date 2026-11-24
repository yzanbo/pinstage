import AppKit
import PinstageCore

/// アプリの入口
///
/// メニューバーに常駐し、ふだんは Dock には出さない（Info.plist の LSUIElement。設定・型の編集を開いている間だけ出す。DockIcon）。
/// ディスプレイの左端にストリップを出し、そこからステージ（最前面に出すウインドウの組み合わせ）を操作する。
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let stage = StageController()
    private let thumbnails = ThumbnailStore()
    private let shortcuts = ShortcutCenter()
    private let actions = AppActions()
    private lazy var strips = StripManager(stage: stage, thumbnails: thumbnails, shortcuts: shortcuts, actions: actions)
    private lazy var editor = LayoutEditorWindowController(stage: stage)
    private lazy var groupEditor = GroupEditorWindowController(stage: stage)
    private lazy var search = SearchController(stage: stage)
    private lazy var stripAvoider = StripAvoider(stage: stage, shownStripScreens: { [weak self] in self?.strips.shownScreens ?? [] })
    private lazy var settingsWindow = SettingsWindowController(stage: stage, thumbnails: thumbnails, shortcuts: shortcuts, editor: editor)
    private lazy var automation = AutomationCenter(stage: stage, strips: strips, search: search)
    private var statusItem: StatusItemController?
    /// 終了の合図（killall など）を受けて、ふつうに終了する
    private var terminateSignal: (any DispatchSourceSignal)?
    /// 起動を終える前に届いた URL（グループを読み込んでから行う）
    private var pendingURLs: [URL] = []
    private var didFinishLaunching = false

    static func main() {
        #if DEBUG
        // 開発用: ストリップの見た目を、見本のデータで画像に描き出して終わる（--render-strip-preview 書き出す場所 [見た目] [幅] [場面]）
        if let index = CommandLine.arguments.firstIndex(of: "--render-strip-preview"), CommandLine.arguments.count > index + 1 {
            _ = NSApplication.shared
            let arguments = CommandLine.arguments
            let look = arguments.count > index + 2 ? StripItemSize(rawValue: arguments[index + 2]) : nil
            let width = arguments.count > index + 3 ? Double(arguments[index + 3]).map { CGFloat($0) } : nil
            let scenario = arguments.count > index + 4 ? StripPreview.Scenario(rawValue: arguments[index + 4]) : nil
            StripPreview.render(to: URL(fileURLWithPath: arguments[index + 1]), look: look ?? .list, width: width, scenario: scenario ?? .normal)
            exit(0)
        }
        // 開発用: ストリップのほかの画面を描き出して終わる（--render-view-preview 書き出す場所 画面）
        if let index = CommandLine.arguments.firstIndex(of: "--render-view-preview"), CommandLine.arguments.count > index + 2,
           let screen = StripPreview.Screen(rawValue: CommandLine.arguments[index + 2]) {
            _ = NSApplication.shared
            StripPreview.render(screen, to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            exit(0)
        }
        #endif
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    /// Dock のアイコンを押したとき（設定・型の編集を開いている間だけ Dock に出る）。開いているウインドウを前に出す
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DockIcon.bringWindowsToFront()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 確認の画面などに出すアイコンを、作ったアイコンにする（Dock に出すときは、DockIcon がもう一度設定する）
        AppIcon.applyToApp()
        handleTerminateSignal()
        actions.openSettings = { [weak self] tab in self?.settingsWindow.show(tab: tab) }
        actions.createLayout = { [weak self] slots in self?.editor.createNew(from: slots) }
        actions.openSearch = { [weak self] in self?.search.show() }
        actions.editGroup = { [weak self] group in self?.groupEditor.edit(group) }
        // 自動化（URL・「ショートカット」アプリ）から操作できるようにする
        AutomationCenter.shared = automation
        stage.onLibraryChanged = { PinstageShortcuts.updateAppShortcutParameters() }

        stage.start()
        strips.start()
        thumbnails.start()
        // 常に出しているストリップの後ろに、ウインドウを入り込ませない
        stripAvoider.start()
        shortcuts.perform = { [weak self] action in self?.perform(action) }
        shortcuts.start()
        statusItem = StatusItemController(stage: stage, strips: strips, shortcuts: shortcuts, actions: actions)
        didFinishLaunching = true
        pendingURLs.forEach(automation.open)
        pendingURLs = []
    }

    /// pinstage://… の URL で開かれた（Stream Deck・Alfred・ターミナルの open などから）
    func application(_ application: NSApplication, open urls: [URL]) {
        guard didFinishLaunching else {
            pendingURLs += urls
            return
        }
        urls.forEach(automation.open)
    }

    func applicationWillTerminate(_ notification: Notification) {
        thumbnails.stop()
        stripAvoider.stop()
        strips.stop()
        stage.stop()
    }

    /// ショートカットが押された
    private func perform(_ action: ShortcutAction) {
        switch action {
        case .search:
            search.toggle()
        case .toggleStrip:
            strips.toggle()
        case .saveStageAsGroup:
            if let screen = StageController.screenUnderPointer { stage.saveStageAsGroup(on: screen) }
        case .recordScreenAsGroup:
            if let screen = StageController.screenUnderPointer { stage.recordScreenAsGroup(on: screen) }
        case .nextGroup:
            stage.recallAdjacentGroup(forward: true)
        case .previousGroup:
            stage.recallAdjacentGroup(forward: false)
        case .nextWindow:
            stage.showAdjacentWindow(forward: true)
        case .previousWindow:
            stage.showAdjacentWindow(forward: false)
        default:
            if let index = action.groupIndex { stage.recallGroup(at: index) }
        }
    }

    /// killall（make run・make stop）で送られる終了の合図でも、すぐには止まらず、ふつうに終了する
    private func handleTerminateSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                NSApp.terminate(nil)
            }
        }
        source.resume()
        terminateSignal = source
    }
}
