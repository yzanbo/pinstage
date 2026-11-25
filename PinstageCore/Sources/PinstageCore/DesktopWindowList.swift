import CoreGraphics

/// デスクトップ別の切り替え一覧。ウインドウバーで並べた順番を保ち、所属が分からないものを別にする。
public struct DesktopWindowList<ID: Hashable> {
    public private(set) var byDesktop: [UInt64: [ID]] = [:]
    public private(set) var unassigned: [ID] = []

    public init(windows: [ID], membership: [ID: Set<UInt64>], desktops: Set<UInt64>) {
        for window in windows {
            let spaces = membership[window, default: []].intersection(desktops)
            if spaces.isEmpty {
                unassigned.append(window)
            } else {
                for space in spaces { byDesktop[space, default: []].append(window) }
            }
        }
    }

    /// 全体の一覧では開いたディスプレイの現在のデスクトップだけを先頭へ移す。残りは元の順。
    public static func puttingCurrentFirst<Desktop>(
        _ desktops: [Desktop], current: UInt64?, id: (Desktop) -> UInt64
    ) -> [Desktop] {
        guard let current, let index = desktops.firstIndex(where: { id($0) == current }), index != desktops.startIndex else { return desktops }
        var ordered = desktops
        let first = ordered.remove(at: index)
        ordered.insert(first, at: 0)
        return ordered
    }
}

/// 一覧をウインドウバーの画面内側に出す。AppKit の画面座標（左下が原点）。
public enum DesktopListGeometry {
    public static func panel(
        size: CGSize, in visible: CGRect, anchor: CGRect? = nil, bar: CGRect? = nil, edge: StripEdge? = nil
    ) -> CGRect {
        let gap: CGFloat = 6
        var width = min(size.width, visible.width)
        var height = min(size.height, visible.height)
        guard let anchor, let bar, let edge else {
            return CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
        }
        var x = anchor.midX - width / 2
        var y = anchor.midY - height / 2
        switch edge {
        case .left:
            x = bar.maxX + gap
            width = min(width, max(0, visible.maxX - x))
        case .right:
            let end = bar.minX - gap
            width = min(width, max(0, end - visible.minX))
            x = end - width
        case .top:
            let end = bar.minY - gap
            height = min(height, max(0, end - visible.minY))
            y = end - height
        case .bottom:
            y = bar.maxY + gap
            height = min(height, max(0, visible.maxY - y))
        }
        return CGRect(
            x: max(visible.minX, min(x, visible.maxX - width)),
            y: max(visible.minY, min(y, visible.maxY - height)),
            width: width, height: height
        )
    }
}
