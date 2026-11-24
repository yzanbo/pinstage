/// ステージに出すウインドウの組み合わせ
///
/// ステージは「いま最前面に出すウインドウ」を、出す順番（後ろほど前面）に並べたもの。
/// ウインドウはどのグループにも縛られないので、出したり外したりしても、保存したグループは変わらない。
public struct StageSelection<ID: Hashable>: Equatable {
    /// 出す順番に並べたウインドウ（後ろほど前面）
    public private(set) var members: [ID]

    public init(_ members: [ID] = []) {
        var seen = Set<ID>()
        self.members = members.filter { seen.insert($0).inserted }
    }

    public var isEmpty: Bool { members.isEmpty }

    public func contains(_ id: ID) -> Bool {
        members.contains(id)
    }

    /// そのウインドウだけを出す（クリック）
    public mutating func showOnly(_ id: ID) {
        members = [id]
    }

    /// 出していなければ足し（いちばん前に）、出していれば外す（⌘＋クリック）
    public mutating func toggle(_ id: ID) {
        if let index = members.firstIndex(of: id) {
            members.remove(at: index)
        } else {
            members.append(id)
        }
    }

    /// 足す（ストリップからステージへのドラッグ）。出していれば、いちばん前に移す
    public mutating func add(_ id: ID) {
        members.removeAll { $0 == id }
        members.append(id)
    }

    /// 外す
    public mutating func remove(_ id: ID) {
        members.removeAll { $0 == id }
    }

    /// 組み合わせごと入れ替える（グループを呼び出したとき）
    public mutating func replace(with ids: [ID]) {
        self = StageSelection(ids)
    }

    /// 閉じたウインドウを外す
    public mutating func prune(keeping existing: Set<ID>) {
        members.removeAll { !existing.contains($0) }
    }
}
