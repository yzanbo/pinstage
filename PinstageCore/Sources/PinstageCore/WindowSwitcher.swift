import CoreGraphics
import Foundation

/// ショートカットで開いたウインドウ切り替え画面にだけ適用する設定。
public struct WindowSwitcherSettings: Equatable, Sendable {
    public enum Grouping: String, CaseIterable, Sendable {
        case byDesktop
        case flat

        public var title: String {
            switch self {
            case .byDesktop: "デスクトップ別"
            case .flat: "まとめて表示"
            }
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

        /// 設定は残したまま、許可のない間だけ一覧を使う。
        public func displayed(hasScreenCapturePermission: Bool) -> Self {
            self == .thumbnails && !hasScreenCapturePermission ? .list : self
        }
    }

    public var grouping: Grouping = .byDesktop
    public var appearance: Appearance = .list

    public init() {}

    public init(defaults: UserDefaults) {
        grouping = defaults.string(forKey: "windowSwitcher.grouping").flatMap(Grouping.init(rawValue:)) ?? .byDesktop
        appearance = defaults.string(forKey: "windowSwitcher.appearance").flatMap(Appearance.init(rawValue:)) ?? .list
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(grouping.rawValue, forKey: "windowSwitcher.grouping")
        defaults.set(appearance.rawValue, forKey: "windowSwitcher.appearance")
    }
}

/// 格子の見た目とキーで移動するときの列数がずれないよう、同じ値から決める。
public enum WindowSwitcherLayout {
    public static let inset: CGFloat = 12
    public static let tileSpacing: CGFloat = 8

    public static func overviewSize(for appearance: WindowSwitcherSettings.Appearance) -> CGSize {
        switch appearance {
        case .list: CGSize(width: 560, height: 450)
        case .icons: CGSize(width: 600, height: 420)
        case .thumbnails: CGSize(width: 760, height: 500)
        }
    }

    public static func columns(for appearance: WindowSwitcherSettings.Appearance, panelWidth: CGFloat) -> Int {
        let minimum: CGFloat
        switch appearance {
        case .list: return 1
        case .icons: minimum = 65
        case .thumbnails: minimum = 156
        }
        let usable = max(0, panelWidth - 2 * inset)
        return max(1, Int((usable + tileSpacing) / (minimum + tileSpacing)))
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
