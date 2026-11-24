import Foundation

/// キーボードショートカット（Carbon のキーの番号と修飾キー）
public struct Shortcut: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    /// 表示用のキーの名前（例: "1"）
    public var key: String

    public init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// 例: "⌃⌥1"（並びは macOS の表示の順 ⌃⌥⇧⌘）
    public var displayString: String {
        ShortcutModifier.allCases.filter { modifiers & $0.carbonValue != 0 }.map(\.symbol).joined() + key
    }

    /// ⌘・⌥・⌃ のどれかを含むか（どれも含まないキーは、ふつうの入力とぶつかるので割り当てない）
    public var hasRequiredModifier: Bool {
        modifiers & (ShortcutModifier.command.carbonValue | ShortcutModifier.option.carbonValue | ShortcutModifier.control.carbonValue) != 0
    }
}

/// 修飾キー（Carbon の値。Carbon を読み込まずに使えるよう、値をここに持つ）
public enum ShortcutModifier: CaseIterable, Sendable {
    case control
    case option
    case shift
    case command

    public var carbonValue: UInt32 {
        switch self {
        case .command: 0x0100
        case .shift: 0x0200
        case .option: 0x0800
        case .control: 0x1000
        }
    }

    public var symbol: String {
        switch self {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .command: "⌘"
        }
    }
}

/// ショートカットを割り当てられる操作
public enum ShortcutAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case search
    case toggleStrip
    case saveStageAsGroup
    case recordScreenAsGroup
    case nextGroup
    case previousGroup
    case nextWindow
    case previousWindow
    case group1, group2, group3, group4, group5, group6, group7, group8, group9

    public var id: String { rawValue }

    /// グループを呼び出す操作の、グループの番号（0 から）
    public var groupIndex: Int? {
        Self.groupActions.firstIndex(of: self)
    }

    public static let groupActions: [ShortcutAction] = [.group1, .group2, .group3, .group4, .group5, .group6, .group7, .group8, .group9]
    public static let stageActions: [ShortcutAction] = [.search, .toggleStrip, .saveStageAsGroup, .recordScreenAsGroup]
    /// 順に切り替える操作
    public static let cycleActions: [ShortcutAction] = [.nextGroup, .previousGroup, .nextWindow, .previousWindow]

    public static func group(at index: Int) -> ShortcutAction? {
        groupActions.indices.contains(index) ? groupActions[index] : nil
    }

    public var title: String {
        switch self {
        case .search: "ウインドウ・グループを検索"
        case .toggleStrip: "ウインドウバーを出す・隠す"
        case .saveStageAsGroup: "ステージをグループとして保存"
        case .recordScreenAsGroup: "見えている画面をグループとして記録"
        case .nextGroup: "次のグループを呼び出す"
        case .previousGroup: "前のグループを呼び出す"
        case .nextWindow: "次のウインドウを出す"
        case .previousWindow: "前のウインドウを出す"
        default: "\((groupIndex ?? 0) + 1) 番目のグループを呼び出す"
        }
    }

    /// 1〜9 のキーの番号（数字の順に並んでいない）と、S・Space・] ・[ のキーの番号
    private static let digitKeyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    private static let keyCodeS: UInt32 = 1
    private static let keyCodeSpace: UInt32 = 49
    private static let keyCodeRightBracket: UInt32 = 30
    private static let keyCodeLeftBracket: UInt32 = 33

    /// 初期設定（検索は ⌃⌥Space、グループは ⌃⌥1〜9、ストリップは ⌃⌥S、次・前のグループは ⌃⌥] ・⌃⌥[）
    public var defaultShortcut: Shortcut? {
        let controlOption = ShortcutModifier.control.carbonValue | ShortcutModifier.option.carbonValue
        if let index = groupIndex {
            return Shortcut(keyCode: Self.digitKeyCodes[index], modifiers: controlOption, key: "\(index + 1)")
        }
        switch self {
        case .search: return Shortcut(keyCode: Self.keyCodeSpace, modifiers: controlOption, key: "Space")
        case .toggleStrip: return Shortcut(keyCode: Self.keyCodeS, modifiers: controlOption, key: "S")
        case .nextGroup: return Shortcut(keyCode: Self.keyCodeRightBracket, modifiers: controlOption, key: "]")
        case .previousGroup: return Shortcut(keyCode: Self.keyCodeLeftBracket, modifiers: controlOption, key: "[")
        // ウインドウの切り替えは、ほかのアプリ（⌃⌥←→ など）とぶつかりやすいので、初期設定では割り当てない
        default: return nil
        }
    }
}

/// 操作ごとのショートカットの割り当て（UserDefaults に保存する）
public struct ShortcutBindings: Equatable, Sendable {
    private var shortcuts: [ShortcutAction: Shortcut]

    public static var defaults: ShortcutBindings {
        ShortcutBindings(Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.compactMap { action in
            action.defaultShortcut.map { (action, $0) }
        }))
    }

    public init(_ shortcuts: [ShortcutAction: Shortcut]) {
        self.shortcuts = shortcuts
    }

    public func shortcut(for action: ShortcutAction) -> Shortcut? {
        shortcuts[action]
    }

    /// 割り当てる（nil なら外す）。同じキーをほかの操作に割り当てていたら、そちらから外し、その操作を返す
    @discardableResult
    public mutating func set(_ shortcut: Shortcut?, for action: ShortcutAction) -> ShortcutAction? {
        var removedFrom: ShortcutAction?
        if let shortcut, let other = shortcuts.first(where: { $0.key != action && $0.value == shortcut })?.key {
            shortcuts[other] = nil
            removedFrom = other
        }
        shortcuts[action] = shortcut
        return removedFrom
    }

    // MARK: - 保存

    private static let key = "shortcuts.bindings"
    /// 保存したときにあった操作（あとから足した操作には、初期設定を入れるため）
    private static let knownKey = "shortcuts.knownActions"

    /// 保存した割り当てを読む（まだ保存していなければ初期設定）。外したものは外したまま読む。
    /// 保存したあとに足した操作は、初期設定のキーにする（ほかの操作が同じキーを使っていれば、割り当てない）
    public init(defaults: UserDefaults) {
        guard let data = defaults.data(forKey: Self.key),
              let stored = try? JSONDecoder().decode([String: Shortcut].self, from: data)
        else {
            self = .defaults
            return
        }
        self.init(Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            ShortcutAction(rawValue: key).map { ($0, value) }
        }))
        // 保存したときにあった操作（記録がなければ、いまの操作がすべてあったものとする）
        let known = (defaults.stringArray(forKey: Self.knownKey)?.compactMap(ShortcutAction.init(rawValue:))).map(Set.init)
            ?? Set(ShortcutAction.allCases)
        for action in ShortcutAction.allCases where !known.contains(action) {
            guard let shortcut = action.defaultShortcut, !shortcuts.values.contains(shortcut) else { continue }
            shortcuts[action] = shortcut
        }
    }

    public func save(to defaults: UserDefaults) {
        let stored = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.key)
        }
        defaults.set(ShortcutAction.allCases.map(\.rawValue), forKey: Self.knownKey)
    }
}
