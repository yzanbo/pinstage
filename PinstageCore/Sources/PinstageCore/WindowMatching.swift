/// 再起動のあとも同じウインドウを見つけるための手がかり
///
/// ウインドウの番号はアプリを起動し直すと変わるので、アプリの識別名とウインドウの名前で覚える。
public struct WindowSignature: Codable, Equatable, Hashable, Sendable {
    /// アプリの識別名（com.apple.Safari など）
    public var bundleID: String
    /// ウインドウの名前（覚えたときのもの）
    public var title: String

    public init(bundleID: String, title: String) {
        self.bundleID = bundleID
        self.title = title
    }
}

/// 覚えたウインドウを、いま開いているウインドウに当てはめる
public enum WindowMatcher {
    /// 1 つの手がかりを当てはめた結果
    public enum Match: Equatable {
        /// いま開いているウインドウ（候補の番号）
        case window(Int)
        /// アプリは動いているが、ウインドウが見つからない
        case missingWindow
        /// アプリが動いていない（起動し直す）
        case appNotRunning

        /// 当てはまったウインドウ（候補の番号）。見つからなければ nil
        public var windowIndex: Int? {
            if case .window(let index) = self { index } else { nil }
        }
    }

    /// - Parameters:
    ///   - signatures: 覚えたウインドウ（グループの中身）
    ///   - candidates: いま開いているウインドウ
    ///   - runningBundleIDs: いま動いているアプリの識別名
    /// - Returns: 手がかりごとの結果（同じウインドウを 2 回は使わない）
    ///
    /// 名前がぴったり同じウインドウを先に当てはめ、残りは同じアプリのまだ使っていないウインドウに当てはめる
    /// （Safari のタブを切り替えるなど、名前が変わることが多いため）。
    public static func match(
        _ signatures: [WindowSignature],
        candidates: [WindowSignature],
        runningBundleIDs: Set<String>
    ) -> [Match] {
        var used = Set<Int>()
        var results = [Match?](repeating: nil, count: signatures.count)

        // 1 回目: 名前がぴったり同じもの
        for (index, signature) in signatures.enumerated() {
            if let hit = candidates.indices.first(where: { !used.contains($0) && candidates[$0] == signature }) {
                used.insert(hit)
                results[index] = .window(hit)
            }
        }
        // 2 回目: 同じアプリのまだ使っていないもの
        for (index, signature) in signatures.enumerated() where results[index] == nil {
            if let hit = candidates.indices.first(where: { !used.contains($0) && candidates[$0].bundleID == signature.bundleID }) {
                used.insert(hit)
                results[index] = .window(hit)
            } else {
                results[index] = runningBundleIDs.contains(signature.bundleID) ? .missingWindow : .appNotRunning
            }
        }
        return results.map { $0 ?? .missingWindow }
    }
}
