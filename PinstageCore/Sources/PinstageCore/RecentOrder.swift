import Foundation

/// ウインドウバーのウインドウの並び（一度並べた順番は変えず、新しく開いたものを足す）
///
/// 新しいウインドウは、同じアプリのウインドウがあれば、その最後のすぐ後ろに入れる（同じアプリをとなりに並べる）。
/// なければ末尾に足す（ブラウザのタブと同じ）。
/// 「同じアプリをまとめる」（StripSettings.groupsSameApp）がオンなら、すでに並んでいるものも、いつも同じアプリをまとめる。
/// オフなら、利用者がドラッグで離したものは、その位置のまま動かさない。
public enum RecentOrder {
    /// いまあるものに合わせる（なくなったものは除き、新しいものを足す）
    /// - Parameters:
    ///   - app: ウインドウのアプリ（同じアプリをとなりに並べる。nil なら末尾に足す）
    ///   - clusters: すでに並んでいるものも、同じアプリをまとめるか
    public static func syncing<ID: Hashable>(_ order: [ID], with current: [ID], clusters: Bool = false, app: (ID) -> String? = { _ in nil }) -> [ID] {
        let currentSet = Set(current)
        let kept = order.filter { currentSet.contains($0) }
        let keptSet = Set(kept)
        let added = current.filter { !keptSet.contains($0) }
        let result = appending(added, to: kept, app: app)
        return clusters ? clustered(result, app: app) : result
    }

    /// 同じアプリのものを、そのアプリがいちばん最初に出てくる位置にまとめた並び（アプリの中の順番・アプリどうしの順番は変えない）。
    /// アプリが分からないものは、それぞれその位置のまま
    public static func clustered<ID>(_ order: [ID], app: (ID) -> String?) -> [ID] {
        var clusters: [[ID]] = []
        var clusterOfApp: [String: Int] = [:]
        for item in order {
            if let key = app(item), let index = clusterOfApp[key] {
                clusters[index].append(item)
            } else {
                if let key = app(item) { clusterOfApp[key] = clusters.count }
                clusters.append([item])
            }
        }
        return clusters.flatMap { $0 }
    }

    /// 新しいものを足した並び。同じアプリのものがあれば、その最後のすぐ後ろに入れ、なければ末尾に足す
    public static func appending<ID>(_ added: [ID], to base: [ID], app: (ID) -> String?) -> [ID] {
        var result = base
        for item in added {
            if let key = app(item), let last = result.lastIndex(where: { app($0) == key }) {
                result.insert(item, at: last + 1)
            } else {
                result.append(item)
            }
        }
        return result
    }
}
