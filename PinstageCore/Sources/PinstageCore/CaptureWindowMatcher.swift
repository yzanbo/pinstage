import CoreGraphics

/// サムネイルを撮るために、アクセシビリティの API のウインドウと、画面収録の API のウインドウを結び付ける
///
/// 2 つの API は別々の番号でウインドウを数えるので、アプリ（プロセス番号）・名前・枠で照らし合わせる。
/// 枠の座標は、どちらも「いちばん目の画面の左上が原点」。
public enum CaptureWindowMatcher {
    /// 照らし合わせるウインドウ
    public struct Window: Equatable, Sendable {
        public var pid: Int32
        public var title: String
        public var frame: CGRect

        public init(pid: Int32, title: String, frame: CGRect) {
            self.pid = pid
            self.title = title
            self.frame = frame
        }
    }

    /// 名前が違うとき、枠のずれ（pt）がこれより小さければ同じウインドウと見なす
    public static let frameTolerance: CGFloat = 40

    /// - Returns: targets ごとの、candidates の番号（見つからなければ nil。同じ候補は 2 回使わない）
    public static func match(_ targets: [Window], candidates: [Window]) -> [Int?] {
        var used = Set<Int>()
        return targets.map { target in
            var best: (index: Int, score: CGFloat)?
            for (index, candidate) in candidates.enumerated() where candidate.pid == target.pid && !used.contains(index) {
                let distance = Self.distance(target.frame, candidate.frame)
                // 名前が分からないとき（画面収録の許可がないと、ほかのアプリのウインドウの名前は空になる）は、位置だけで照らし合わせる
                let sameTitle = !candidate.title.isEmpty && candidate.title == target.title
                guard sameTitle || distance < frameTolerance else { continue }
                // 名前が同じものを先に選び、その中で枠が近いものを選ぶ
                let score = (sameTitle ? 0 : 10_000) + distance
                if best == nil || score < best!.score { best = (index, score) }
            }
            if let best { used.insert(best.index) }
            return best?.index
        }
    }

    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }
}
