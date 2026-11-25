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
