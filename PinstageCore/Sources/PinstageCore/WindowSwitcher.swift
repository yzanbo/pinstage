import CoreGraphics
import Foundation

/// ウインドウスイッチャーの表示と操作の設定（ウインドウバーとは別）。
public struct WindowSwitcherSettings: Equatable, Sendable {
    public static let title = "ウインドウスイッチャー"

    public enum Grouping: String, CaseIterable, Sendable {
        case byDesktop
        case flat

        public var title: String {
            switch self {
            case .byDesktop: "デスクトップ別"
            case .flat: "まとめて表示"
            }
        }

        /// もう一方のグループ分け（切り替え画面の中の ⌘G で入れ替える）
        public var toggled: Self {
            self == .byDesktop ? .flat : .byDesktop
        }
    }

    public enum Appearance: String, CaseIterable, Sendable {
        case list
        case icons
        case thumbnails

        public var title: String {
            switch self {
            case .list: "一覧"
            case .icons: "アイコンだけ"
            case .thumbnails: "サムネイル"
            }
        }

        /// 切り替え画面の中で選ぶときの印（ウインドウバーの形式の印と同じ形）
        public var symbolName: String {
            switch self {
            case .list: "list.bullet.rectangle"
            case .icons: "square.grid.3x2"
            case .thumbnails: "photo"
            }
        }

        /// 切り替え画面の中で、⌘＋数字で選ぶときの見た目（⌘1 一覧・⌘2 アイコンだけ・⌘3 サムネイル）
        public init?(shortcutNumber: Int) {
            let all = Self.allCases
            guard (1...all.count).contains(shortcutNumber) else { return nil }
            self = all[shortcutNumber - 1]
        }

        /// 設定は残したまま、画面収録の許可のない間だけ、サムネイルの代わりにアイコンだけで表示する（格子のまま、許可が要らない）
        public func displayed(hasScreenCapturePermission: Bool) -> Self {
            self == .thumbnails && !hasScreenCapturePermission ? .icons : self
        }
    }

    public enum DisplaySize: String, CaseIterable, Sendable {
        case small
        case medium
        case large

        public var title: String {
            switch self {
            case .small: "小"
            case .medium: "中"
            case .large: "大"
            }
        }

        fileprivate func scaled(_ value: CGFloat) -> CGFloat {
            switch self {
            case .small: (value * 0.75).rounded()
            case .medium: value
            case .large: (value * 1.25).rounded()
            }
        }
    }

    public enum Confirmation: String, CaseIterable, Sendable {
        case onModifierRelease
        case explicit

        public var title: String {
            switch self {
            case .onModifierRelease: "修飾キーを離して確定"
            case .explicit: "Enterで確定"
            }
        }
    }

    public var grouping: Grouping = .byDesktop
    public var appearance: Appearance = .icons
    public var displaySize: DisplaySize = .medium
    public var confirmation: Confirmation = .onModifierRelease

    public init() {}

    public init(defaults: UserDefaults) {
        grouping = defaults.string(forKey: "windowSwitcher.grouping").flatMap(Grouping.init(rawValue:)) ?? .byDesktop
        appearance = defaults.string(forKey: "windowSwitcher.appearance").flatMap(Appearance.init(rawValue:)) ?? .icons
        displaySize = defaults.string(forKey: "windowSwitcher.displaySize").flatMap(DisplaySize.init(rawValue:)) ?? .medium
        confirmation = defaults.string(forKey: "windowSwitcher.confirmation").flatMap(Confirmation.init(rawValue:)) ?? .onModifierRelease
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(grouping.rawValue, forKey: "windowSwitcher.grouping")
        defaults.set(appearance.rawValue, forKey: "windowSwitcher.appearance")
        defaults.set(displaySize.rawValue, forKey: "windowSwitcher.displaySize")
        defaults.set(confirmation.rawValue, forKey: "windowSwitcher.confirmation")
    }
}

/// 開いた回に自動確定を待つ修飾キー。キーのイベントと表示直後の確認が両方来ても、一度しか確定しない。
public struct WindowSwitcherRelease<Modifiers: OptionSet> {
    private var pending: Modifiers

    public init(confirmation: WindowSwitcherSettings.Confirmation, shortcutModifiers: Modifiers?) {
        pending = confirmation == .onModifierRelease ? shortcutModifiers ?? [] : []
    }

    public var isWaiting: Bool { !pending.isEmpty }

    public mutating func cancel() { pending = [] }

    public mutating func consumeIfReleased(_ held: Modifiers) -> Bool {
        guard isWaiting, held.isDisjoint(with: pending) else { return false }
        cancel()
        return true
    }
}

/// 格子の見た目とキーで移動するときの列数・画面の大きさがずれないよう、同じ値から決める。
public enum WindowSwitcherLayout {
    public typealias DisplaySize = WindowSwitcherSettings.DisplaySize
    public static let inset: CGFloat = 16
    public static let tileSpacing: CGFloat = 10

    // MARK: 画面の大きさ（画面に合わせて大きく出す）

    /// 画面に対する、切り替え画面の幅・高さの上限の割合
    public static let maximumWidthShare: CGFloat = 0.72
    public static let maximumHeightShare: CGFloat = 0.8

    /// 見た目ごとの、ちょうどよい幅（画面が狭ければ、画面の割合で止める）
    public static func preferredWidth(for appearance: WindowSwitcherSettings.Appearance) -> CGFloat {
        switch appearance {
        case .list: 760
        case .icons: 1040
        case .thumbnails: 1240
        }
    }

    /// 切り替え画面の幅（画面の使える範囲の幅から）
    public static func overviewWidth(for appearance: WindowSwitcherSettings.Appearance, visibleWidth: CGFloat) -> CGFloat {
        min(preferredWidth(for: appearance), (visibleWidth * maximumWidthShare).rounded(.down))
    }

    /// 開き方に関係なく、対象ディスプレイの表示領域の中央に収める（AppKit の画面座標）。
    public static func panelFrame(size: CGSize, in visible: CGRect) -> CGRect {
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        return CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }

    // MARK: 中身の寸法（画面の高さを中身に合わせるため。ビューも同じ値で描く）

    /// 上の見出し（題・絞り込み・表示の切り替え）の高さ
    public static let headerHeight: CGFloat = 28
    /// 見出し・一覧・下の案内の間
    public static let blockSpacing: CGFloat = 10
    /// デスクトップの見出しの高さと、その下の間
    public static let sectionTitleHeight: CGFloat = 20
    public static let sectionTitleSpacing: CGFloat = 6
    /// ディスプレイごとの枠。単一のディスプレイや「まとめて表示」では使わない。
    public static let displayGroupInset: CGFloat = 12
    public static let displayTitleHeight: CGFloat = 20
    public static let displayTitleSpacing: CGFloat = 8
    /// デスクトップとデスクトップの間
    public static let sectionSpacing: CGFloat = 14
    /// 一覧の行の間
    public static let listRowSpacing: CGFloat = 4
    /// 「ウインドウはありません」の高さ
    public static let emptySectionHeight: CGFloat = 18
    /// 画面収録の許可の案内の高さ
    public static let noticeHeight: CGFloat = 16
    /// 下の「選んでいるウインドウの名前」「選んだ数」の高さ（区切りの線と、その下の間を含む）
    public static let footerSpacing: CGFloat = 10
    public static let footerContentHeight: CGFloat = 20
    public static let footerHeight: CGFloat = 1 + footerSpacing + footerContentHeight
    /// 下の操作の案内の高さ
    public static let hintsHeight: CGFloat = 16
    /// いちばん低い高さ（ウインドウが少なくても、見出しと案内が窮屈にならないように）
    public static let minimumOverviewHeight: CGFloat = 220

    public static func listRowHeight(for size: DisplaySize) -> CGFloat { size.scaled(46) }
    public static func listIconSize(for size: DisplaySize) -> CGFloat { size.scaled(30) }
    public static func iconSize(for size: DisplaySize) -> CGFloat { size.scaled(64) }
    public static func thumbnailImageHeight(for size: DisplaySize) -> CGFloat { size.scaled(150) }
    public static func thumbnailFallbackIconSize(for size: DisplaySize) -> CGFloat { size.scaled(56) }

    public static let tileContentSpacing: CGFloat = 6

    public static func tileCaptionHeight(for appearance: WindowSwitcherSettings.Appearance) -> CGFloat {
        appearance == .thumbnails ? 18 : 16
    }

    public static func tileVerticalPadding(for appearance: WindowSwitcherSettings.Appearance) -> CGFloat {
        appearance == .thumbnails ? 8 : 10
    }

    /// 格子のタイル 1 つの高さ（一覧では、1 行の高さ）
    public static func tileHeight(for appearance: WindowSwitcherSettings.Appearance, size: DisplaySize = .medium) -> CGFloat {
        guard appearance != .list else { return listRowHeight(for: size) }
        let imageHeight = appearance == .thumbnails ? thumbnailImageHeight(for: size) : iconSize(for: size)
        return imageHeight + tileContentSpacing + tileCaptionHeight(for: appearance) + 2 * tileVerticalPadding(for: appearance)
    }

    /// 格子のタイルのいちばん狭い幅
    private static func minimumTileWidth(for appearance: WindowSwitcherSettings.Appearance, size: DisplaySize) -> CGFloat {
        switch appearance {
        case .list: 0
        case .icons: size.scaled(110)
        case .thumbnails: size.scaled(250)
        }
    }

    /// 切り替え画面の高さ。中身（見出し・各デスクトップの見出しと行・下の名前・案内）に合わせ、
    /// いちばん低い高さと、上限（画面の高さの割合）の間に収める（多いときはスクロール）
    /// - Parameters:
    ///   - sectionCounts: デスクトップごとのウインドウの数（まとめて表示なら 1 つ）
    ///   - titledSections: デスクトップの見出しを出すか（まとめて表示では出さない）
    ///   - columns: 格子の列の数
    ///   - maximumHeight: 高さの上限（画面の使える範囲の高さ × 割合）
    ///   - displayGroupCount: ディスプレイ名付きの枠を出すグループの数
    ///   - showsNotice: 画面収録の許可の案内を出すか
    ///   - showsFooter: 下に、選んでいるウインドウの名前・選んだ数を出すか
    public static func overviewHeight(
        for appearance: WindowSwitcherSettings.Appearance, size: DisplaySize = .medium, sectionCounts: [Int], titledSections: Bool,
        columns: Int, maximumHeight: CGFloat, displayGroupCount: Int = 0, showsNotice: Bool = false, showsFooter: Bool = true
    ) -> CGFloat {
        var content = CGFloat(displayGroupCount) * (2 * displayGroupInset + displayTitleHeight + displayTitleSpacing)
        for (index, count) in sectionCounts.enumerated() {
            if index > 0 { content += sectionSpacing }
            if titledSections { content += sectionTitleHeight + sectionTitleSpacing }
            content += bodyHeight(for: appearance, size: size, count: count, columns: columns)
        }
        var height = inset * 2 + headerHeight + blockSpacing + content
        if showsNotice { height += blockSpacing + noticeHeight }
        if showsFooter { height += blockSpacing + footerHeight }
        height += blockSpacing + hintsHeight
        return min(max(height.rounded(.up), minimumOverviewHeight), max(minimumOverviewHeight, maximumHeight))
    }

    /// 1 つのデスクトップの中身の高さ（見出しを除く）
    private static func bodyHeight(
        for appearance: WindowSwitcherSettings.Appearance, size: DisplaySize, count: Int, columns: Int
    ) -> CGFloat {
        guard count > 0 else { return emptySectionHeight }
        if appearance == .list {
            return CGFloat(count) * listRowHeight(for: size) + CGFloat(count - 1) * listRowSpacing
        }
        let rows = (count + max(1, columns) - 1) / max(1, columns)
        return CGFloat(rows) * tileHeight(for: appearance, size: size) + CGFloat(rows - 1) * tileSpacing
    }

    public static func columns(
        for appearance: WindowSwitcherSettings.Appearance, size: DisplaySize = .medium, panelWidth: CGFloat,
        showsDisplayGroups: Bool = false
    ) -> Int {
        guard appearance != .list else { return 1 }
        let minimum = minimumTileWidth(for: appearance, size: size)
        let usable = max(0, panelWidth - 2 * (inset + (showsDisplayGroups ? displayGroupInset : 0)))
        return max(1, Int((usable + tileSpacing) / (minimum + tileSpacing)))
    }
}

/// 切り替え画面で、文字を打って絞り込む（ウインドウ名かアプリ名に、打った言葉がすべて含まれるもの。決まりは検索と同じ）
public struct WindowSwitcherFilter: Sendable {
    private let terms: [String]

    public init(query: String) {
        terms = SearchMatcher.terms(query)
    }

    public func matches(title: String, appName: String) -> Bool {
        guard !terms.isEmpty else { return true }
        return SearchMatcher.score(SearchItem(id: 0, title: title, subtitle: appName), terms: terms) != nil
    }
}

/// 切り替え画面で選んでいる行。格子で上下に移るときは、できるだけ同じ列に置く。
public enum WindowSwitcherNavigation {
    public struct Position: Equatable {
        public let section: Int
        public let item: Int

        public init(section: Int, item: Int) {
            self.section = section
            self.item = item
        }
    }

    public enum Direction {
        case left, right, up, down
    }

    /// Tab（forward）・⇧Tab で、並びの順に 1 つ進める・戻す。最後の次は最初、最初の前は最後（空のデスクトップは飛ばす）
    public static func stepping(from current: Position?, forward: Bool, counts: [Int]) -> Position? {
        let all = counts.indices.flatMap { section in (0..<max(0, counts[section])).map { Position(section: section, item: $0) } }
        guard !all.isEmpty else { return nil }
        guard let current, let index = all.firstIndex(of: current) else { return forward ? all.first : all.last }
        return all[(index + (forward ? 1 : all.count - 1)) % all.count]
    }

    public static func moving(
        from current: Position, _ direction: Direction, counts: [Int], columns: Int
    ) -> Position {
        let section = current.section
        let item = current.item
        guard counts.indices.contains(section), (0..<max(0, counts[section])).contains(item) else { return current }
        let width = max(1, columns)
        let forward = direction == .right || direction == .down
        let vertical = direction == .up || direction == .down
        let next = item + (forward ? 1 : -1) * (vertical ? width : 1)
        let count = counts[section]
        if (0..<count).contains(next) { return Position(section: section, item: next) }
        // 次の行が途中までしかないときは、その行の右端で止まる。
        if direction == .down, item / width < (count - 1) / width {
            return Position(section: section, item: count - 1)
        }
        let filled = counts.indices.filter { counts[$0] > 0 }
        let other = forward ? filled.first { $0 > section } : filled.last { $0 < section }
        guard let other else { return current }
        let last = counts[other] - 1
        let offset = vertical ? item % width : 0
        let firstInRow = forward ? 0 : vertical ? (last / width) * width : last
        return Position(section: other, item: min(firstInRow + offset, last))
    }
}
