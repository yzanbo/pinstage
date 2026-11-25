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
}

/// 最初に現れたディスプレイ順にまとめる。ディスプレイ内では元の並びを変えない。
public struct DesktopDisplayGroup<DisplayID: Hashable, Item>: Identifiable {
    public let id: DisplayID
    public private(set) var items: [Item]

    public init(id: DisplayID, items: [Item]) {
        self.id = id
        self.items = items
    }

    /// 内容を絞り直しても所属は引き継ぐ。空になったグループは出さない。
    public func compactMapItems<Result>(_ transform: (Item) -> Result?) -> DesktopDisplayGroup<DisplayID, Result>? {
        let shown = items.compactMap(transform)
        return shown.isEmpty ? nil : DesktopDisplayGroup<DisplayID, Result>(id: id, items: shown)
    }

    /// 優先する項目があればその項目と所属グループを先頭へ。それ以外は相対順を保つ。
    public static func grouping(
        _ items: [Item], by display: (Item) -> DisplayID, prioritizing preferred: ((Item) -> Bool)? = nil
    ) -> [Self] {
        var ordered = items
        if let preferred, let index = ordered.firstIndex(where: preferred), index != ordered.startIndex {
            let first = ordered.remove(at: index)
            ordered.insert(first, at: 0)
        }
        var groups: [Self] = []
        var indices: [DisplayID: Int] = [:]
        for item in ordered {
            let id = display(item)
            if let index = indices[id] {
                groups[index].items.append(item)
            } else {
                indices[id] = groups.count
                groups.append(Self(id: id, items: [item]))
            }
        }
        return groups
    }
}
