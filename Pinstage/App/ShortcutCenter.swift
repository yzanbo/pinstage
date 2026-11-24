import AppKit
import Carbon.HIToolbox
import Observation
import PinstageCore

/// どこからでも使えるショートカットの割り当てと登録
///
/// 割り当ては設定画面で変えられ、UserDefaults に保存する。初期設定は ⌃⌥Space（検索）・⌃⌥1〜9（グループ）・⌃⌥S（ストリップ）・⌃⌥] / ⌃⌥[（次・前のグループ）。
@Observable
final class ShortcutCenter {
    private(set) var bindings = ShortcutBindings(defaults: .standard)
    /// 登録できなかった操作（ほかのアプリが同じキーを使っているなど）
    private(set) var unavailable: Set<ShortcutAction> = []
    /// 設定画面で記録している操作
    var recordingAction: ShortcutAction?

    /// ショートカットが押された
    @ObservationIgnored var perform: (ShortcutAction) -> Void = { _ in }
    @ObservationIgnored private var hotKeys: [HotKey] = []

    func start() {
        register()
    }

    func shortcut(for action: ShortcutAction) -> Shortcut? {
        bindings.shortcut(for: action)
    }

    /// 割り当てる（nil なら外す）。同じキーをほかの操作から外したら、その操作を返す
    @discardableResult
    func set(_ shortcut: Shortcut?, for action: ShortcutAction) -> ShortcutAction? {
        let removed = bindings.set(shortcut, for: action)
        bindings.save(to: .standard)
        register()
        return removed
    }

    func resetToDefaults() {
        bindings = .defaults
        bindings.save(to: .standard)
        register()
    }

    /// 記録している間は、すべてのショートカットを止める（押したキーが設定画面に届くように）
    func pause() {
        hotKeys = []
    }

    func resume() {
        register()
    }

    /// 割り当てをすべて登録し直す（前の登録は HotKey を手放すと外れる）
    private func register() {
        hotKeys = []
        var failed: Set<ShortcutAction> = []
        for action in ShortcutAction.allCases {
            guard let shortcut = bindings.shortcut(for: action) else { continue }
            if let hotKey = HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, action: { [weak self] in self?.perform(action) }) {
                hotKeys.append(hotKey)
            } else {
                failed.insert(action)
            }
        }
        unavailable = failed
    }
}

extension Shortcut {
    /// キーを押したイベントからショートカットを作る。⌘・⌥・⌃ のどれも押していなければ nil
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= ShortcutModifier.control.carbonValue }
        if flags.contains(.option) { modifiers |= ShortcutModifier.option.carbonValue }
        if flags.contains(.shift) { modifiers |= ShortcutModifier.shift.carbonValue }
        if flags.contains(.command) { modifiers |= ShortcutModifier.command.carbonValue }
        let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: Self.keyName(for: event.keyCode))
        guard shortcut.hasRequiredModifier else { return nil }
        self = shortcut
    }

    /// メニューに出すときの修飾キー
    var menuModifierMask: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & ShortcutModifier.control.carbonValue != 0 { flags.insert(.control) }
        if modifiers & ShortcutModifier.option.carbonValue != 0 { flags.insert(.option) }
        if modifiers & ShortcutModifier.shift.carbonValue != 0 { flags.insert(.shift) }
        if modifiers & ShortcutModifier.command.carbonValue != 0 { flags.insert(.command) }
        return flags
    }

    private static let specialKeys: [UInt16: String] = [
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_DownArrow): "↓", UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
    ]

    /// キーの番号から、いまのキーボード配列でのキーの名前を得る（shift などを押していない状態の文字。Pinshot と同じ）
    static func keyName(for keyCode: UInt16) -> String {
        if let name = specialKeys[keyCode] { return name }
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "?" }

        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}
