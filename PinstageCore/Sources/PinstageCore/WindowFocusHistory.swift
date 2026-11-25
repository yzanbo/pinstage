/// 前面で使ったウインドウの順番。ウインドウバーの並びや永続化する設定には影響させない。
public struct WindowFocusHistory<ID: Hashable>: Equatable {
    private var recent: [ID] = []

    public init() {}

    public var mostRecent: ID? { recent.first }

    public mutating func record(_ id: ID) {
        guard recent.first != id else { return }
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
    }

    public mutating func prune(keeping open: Set<ID>) {
        recent.removeAll { !open.contains($0) }
    }

    /// まだ使っていないウインドウは、ウインドウバーの順で後ろに並べる。
    public func ordered(_ windows: [ID]) -> [ID] {
        var remaining = Set(windows)
        let visited = recent.filter { remaining.remove($0) != nil }
        return visited + windows.filter { remaining.remove($0) != nil }
    }
}
