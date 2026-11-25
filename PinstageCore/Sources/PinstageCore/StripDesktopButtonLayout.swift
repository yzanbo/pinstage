import CoreGraphics

/// 個別のデスクトップボタンを、ディスプレイごとにまとめて出す領域の寸法。
public struct StripDesktopButtonLayout {
    public static let buttonHeight: CGFloat = 24
    public static let buttonSpacing: CGFloat = 3
    public static let groupSpacing: CGFloat = 8

    private static let maxRowWidth: CGFloat = 132
    private static let maxVisibleRows = 4

    public let rowWidth: CGFloat
    public let columnHeight: CGFloat
    public let columnScrolls: Bool

    public init(groups: [(count: Int, showsDisplayNumber: Bool)]) {
        let nonempty = groups.filter { $0.count > 0 }
        let count = nonempty.reduce(0) { $0 + $1.count }
        let gaps = CGFloat(count - nonempty.count) * Self.buttonSpacing
            + CGFloat(max(0, nonempty.count - 1)) * Self.groupSpacing
        let width = nonempty.reduce(CGFloat.zero) { width, group in
            width + CGFloat(group.count) * Self.compactWidth(showsDisplayNumber: group.showsDisplayNumber)
        }
        let rows = min(count, Self.maxVisibleRows)
        let rowSpacing = nonempty.count > 1 ? Self.groupSpacing : Self.buttonSpacing
        rowWidth = min(Self.maxRowWidth, width + gaps)
        columnHeight = min(
            CGFloat(count) * Self.buttonHeight + gaps,
            CGFloat(rows) * Self.buttonHeight + CGFloat(max(0, rows - 1)) * rowSpacing
        )
        columnScrolls = count > Self.maxVisibleRows
    }

    public static func compactWidth(showsDisplayNumber: Bool) -> CGFloat {
        showsDisplayNumber ? 38 : 26
    }
}
