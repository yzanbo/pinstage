import AppKit
import PinstageCore

/// メニューバーのアイコンとメニュー（ストリップの出し入れ・出し方・型・設定・アップデートを確認・終了）
///
/// 自動で新しい版を見つけたら、アイコンの右上に小さな丸を付け、メニューのいちばん上で知らせる（Pinshelf と同じ）
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let stage: StageController
    private let strips: StripManager
    private let shortcuts: ShortcutCenter
    private let actions: AppActions
    /// 更新の状態（新しい版の知らせ・「アップデートを確認…」）
    private let updates: AppUpdates
    /// 新しい版があるときに、アイコンの右上に出す小さな丸
    private let updateBadge = UpdateBadgeView()

    private static let toolTip = "Pinstage"

    init(stage: StageController, strips: StripManager, shortcuts: ShortcutCenter, actions: AppActions, updates: AppUpdates) {
        self.stage = stage
        self.strips = strips
        self.shortcuts = shortcuts
        self.actions = actions
        self.updates = updates
        super.init()
        if let button = statusItem.button {
            // アプリのアイコンと同じ絵の、1 色の印（テンプレート画像）
            button.image = AppIcon.symbol(accessibilityDescription: "Pinstage")
            button.toolTip = Self.toolTip
            installUpdateBadge(on: button)
        }
        updates.onPendingVersionChange = { [weak self] version in
            self?.showPendingUpdate(version)
        }
        showPendingUpdate(updates.pendingVersion)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// メニューの項目に、その操作のショートカットを出す。
    /// メニューに出せるのは 1 文字のキーだけ（Space・F1 などは出さない。ショートカットそのものは効く）
    private func showShortcut(for action: ShortcutAction, on item: NSMenuItem) {
        guard let shortcut = shortcuts.shortcut(for: action), shortcut.key.count == 1 else { return }
        item.keyEquivalent = shortcut.key.lowercased()
        item.keyEquivalentModifierMask = shortcut.menuModifierMask
    }

    /// メニューを開くたびに作り直す（設定のチェックとショートカットを今の値に合わせるため）
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // 自動で見つけた新しい版は、いちばん上で知らせる（選ぶと、更新の画面が出る）
        if let version = updates.pendingVersion {
            let update = item("新しいバージョン \(version) があります…", action: #selector(checkForUpdates))
            update.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
            menu.addItem(update)
            menu.addItem(.separator())
        }

        let toggle = item(strips.anyShown ? "ウインドウバーを隠す" : "ウインドウバーを出す", action: #selector(toggleStrip))
        showShortcut(for: .toggleStrip, on: toggle)
        menu.addItem(toggle)
        let search = item("検索…", action: #selector(openSearch))
        showShortcut(for: .search, on: search)
        menu.addItem(search)
        menu.addItem(.separator())

        menu.addItem(.sectionHeader(title: "ウインドウバー"))
        for mode in StripMode.allCases {
            let modeItem = item(mode.title, action: #selector(selectMode(_:)))
            modeItem.representedObject = mode.rawValue
            modeItem.state = stage.stripSettings.mode == mode ? .on : .off
            menu.addItem(modeItem)
        }

        menu.addItem(.separator())
        menu.addItem(item("新しい型…", action: #selector(newLayout)))
        if !stage.isTrusted {
            menu.addItem(item("アクセシビリティの許可を設定…", action: #selector(openAccessibility)))
        }
        menu.addItem(.separator())
        let settings = item("設定…", action: #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        // 更新の機能を使えるビルドだけ（公開鍵の入っていないビルドでは出さない）
        if updates.isAvailable {
            let check = item("アップデートを確認…", action: #selector(checkForUpdates))
            // 裏で確かめている途中・ダウンロードの途中は選べない
            check.isEnabled = updates.canCheck
            menu.addItem(check)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Pinstage を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleStrip() { strips.toggle() }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = StripMode(rawValue: raw) else { return }
        stage.stripSettings.mode = mode
    }

    @objc private func newLayout() { actions.createLayout([]) }
    @objc private func openSearch() { actions.openSearch() }
    @objc private func openSettings() { actions.openSettings(nil) }
    @objc private func openAccessibility() { AccessibilityPermission.openSettings() }
    @objc private func checkForUpdates() { updates.check() }

    // MARK: - 新しい版の知らせ

    /// アイコンの右上に、小さな丸を置く（ふだんは隠しておく）
    private func installUpdateBadge(on button: NSStatusBarButton) {
        updateBadge.isHidden = true
        updateBadge.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(updateBadge)
        NSLayoutConstraint.activate([
            updateBadge.widthAnchor.constraint(equalToConstant: UpdateBadgeView.diameter),
            updateBadge.heightAnchor.constraint(equalToConstant: UpdateBadgeView.diameter),
            updateBadge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -2),
            updateBadge.topAnchor.constraint(equalTo: button.topAnchor, constant: 3),
        ])
    }

    /// 知らせる新しい版があれば丸を出し、なければ隠す
    private func showPendingUpdate(_ version: String?) {
        updateBadge.isHidden = version == nil
        statusItem.button?.toolTip = version.map { "Pinstage（新しいバージョン \($0) があります）" } ?? Self.toolTip
    }
}

/// 新しい版があるときに、メニューバーのアイコンの右上に出す小さな丸
private final class UpdateBadgeView: NSView {
    static let diameter: CGFloat = 6

    override func draw(_ dirtyRect: NSRect) {
        // 色は描くたびに決める（外観やアクセントカラーが変わっても合うように）
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }

    /// アイコンのクリックを邪魔しない
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
