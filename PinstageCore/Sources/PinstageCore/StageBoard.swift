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
    public mutating func update(on display: String, _ change: (inout Stage) -> Void) {
        var stage = self.stage(on: display)
        change(&stage)
        stages[display] = stage
        let members = Set(stage.selection.members)
        for key in stages.keys where key != display {
            guard var other = stages[key] else { continue }
            other.selection.prune(keeping: Set(other.selection.members).subtracting(members))
            stages[key] = other
        }
    }

    /// 閉じたウインドウを、すべてのステージから外す
    public mutating func prune(keeping existing: Set<ID>) {
        for key in stages.keys {
            stages[key]?.selection.prune(keeping: existing)
        }
    }
}
