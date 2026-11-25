/// ディスプレイごとのステージ
///
/// ディスプレイごとに、最前面に出すウインドウの組み合わせと並べ方を持つ。
/// 1 つのウインドウは 1 か所にしか置けないので、あるディスプレイのステージに入れたら、ほかのディスプレイのステージからは外す。
public struct StageBoard<ID: Hashable>: Equatable {
    /// 1 つのディスプレイのステージ
    public struct Stage: Equatable {
        public var selection = StageSelection<ID>()
        public var layout: LayoutChoice = .builtIn(.auto)

        public init() {}
    }

    /// ディスプレイの UUID ごとのステージ
    public private(set) var stages: [String: Stage] = [:]

    public init() {}

    public func stage(on display: String) -> Stage {
        stages[display] ?? Stage()
    }

    /// あるディスプレイのステージを変える。変えたあとに入っているウインドウは、ほかのディスプレイのステージから外す
    /// - Returns: ウインドウが外れた、ほかのディスプレイ（残りを、空いたところを詰めて並べ直すため）
    @discardableResult
    public mutating func update(on display: String, _ change: (inout Stage) -> Void) -> Set<String> {
        var stage = self.stage(on: display)
        change(&stage)
        stages[display] = stage
        let members = Set(stage.selection.members)
        var pruned: Set<String> = []
        for key in stages.keys where key != display {
            guard var other = stages[key] else { continue }
            // prune は外すだけなので、数が減ったら外れた
            let count = other.selection.members.count
            other.selection.prune(keeping: Set(other.selection.members).subtracting(members))
            if other.selection.members.count != count { pruned.insert(key) }
            stages[key] = other
        }
        return pruned
    }

    /// 外で前に出したウインドウに選択だけを合わせる。すでに組み合わせに入っていれば、そのまま保つ。
    /// - Returns: 選択が変わったか（並べ方は変えない）
    @discardableResult
    public mutating func followFocus(of id: ID, on display: String) -> Bool {
        guard !stages.values.contains(where: { $0.selection.contains(id) }) else { return false }
        update(on: display) { $0.selection.showOnly(id) }
        return true
    }

    /// 閉じたウインドウを、すべてのステージから外す
    public mutating func prune(keeping existing: Set<ID>) {
        for key in stages.keys {
            stages[key]?.selection.prune(keeping: existing)
        }
    }
}
