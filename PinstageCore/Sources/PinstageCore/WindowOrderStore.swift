import Foundation

/// ストリップのウインドウの並び順を、再起動のあとも残す
///
/// ウインドウの番号は起動し直すと変わるので、アプリの識別名とウインドウの名前で覚え、グループと同じく照らし合わせる。
public enum WindowOrderStore {
    private static let key = "strip.windowOrder"

    public static func load(from defaults: UserDefaults) -> [WindowSignature] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([WindowSignature].self, from: data)) ?? []
    }

    public static func save(_ order: [WindowSignature], to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(order) {
            defaults.set(data, forKey: key)
        }
    }

    /// 覚えた並び順に、いまのウインドウを並べ直した順番（current の番号の並び）
    ///
    /// 覚えた並びに当てはまらなかったウインドウ（止めている間に開いたものなど）は、新しいものとして足す
    /// （同じアプリのウインドウがあれば、そのすぐ後ろ。なければ末尾）。
    public static func restoredOrder(saved: [WindowSignature], current: [WindowSignature]) -> [Int] {
        let matches = WindowMatcher.match(saved, candidates: current, runningBundleIDs: [])
        let matched = matches.compactMap(\.windowIndex)
        let matchedSet = Set(matched)
        let unmatched = current.indices.filter { !matchedSet.contains($0) }
        return RecentOrder.appending(unmatched, to: matched) { current[$0].bundleID }
    }
}
