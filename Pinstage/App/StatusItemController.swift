import AppKit
import PinstageCore

/// メニューバーのアイコンとメニュー（ストリップの出し入れ・出し方・型・設定・終了）
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let stage: StageController
    private let strips: StripManager
    private let shortcuts: ShortcutCenter
    private let actions: AppActions

    init(stage: StageController, strips: StripManager, shortcuts: ShortcutCenter, actions: AppActions) {
        self.stage = stage
        self.strips = strips
        self.shortcuts = shortcuts
        self.actions = actions
        super.init()
        if let button = statusItem.button {
            // アプリのアイコンと同じ絵の、1 色の印（テンプレート画像）
            button.image = AppIcon.symbol(accessibilityDescription: "Pinstage")
            button.toolTip = "Pinstage"
        }
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

        let toggle = item(strips.anyShown ? "ストリップを隠す" : "ストリップを出す", action: #selector(toggleStrip))
        showShortcut(for: .toggleStrip, on: toggle)
        menu.addItem(toggle)
        let search = item("検索…", action: #selector(openSearch))
        showShortcut(for: .search, on: search)
        menu.addItem(search)
        menu.addItem(.separator())

        menu.addItem(.sectionHeader(title: "ストリップ"))
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
}
