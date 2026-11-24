import CoreGraphics

/// ドラッグで一覧の並び順を変える計算（ストリップのウインドウ・グループ）
public enum ListReorder {
    /// 落とす位置（0〜count。その番号の行の前に入れる。count なら最後）を、ポインタの高さから決める
    ///
    /// - Parameters:
    ///   - y: ポインタの高さ（行の枠と同じ座標。下へ行くほど大きい）
    ///   - frames: 行の番号ごとの枠（画面に出ていない行はなくてよい）
    ///   - count: 行の数
    public static func dropIndex(forY y: CGFloat, frames: [Int: CGRect], count: Int) -> Int {
        for index in 0..<count {
            if let frame = frames[index], y < frame.midY { return index }
        }
        return count
    }

    /// 横に並べた一覧（上下に出したストリップ）で、落とす位置を、ポインタの x から決める（その番号のものの前に入れる。count なら最後）
    public static func dropIndex(forX x: CGFloat, frames: [Int: CGRect], count: Int) -> Int {
        for index in 0..<count {
            if let frame = frames[index], x < frame.midX { return index }
        }
        return count
    }

    /// アイコンを格子に並べたときの、落とす位置（左から右へ、上から下へ並ぶ順番。その番号の前に入れる）
    ///
    /// ポインタより下の行の最初、またはポインタと同じ行でポインタより右にある（真ん中より右の）ものの前に入れる。
    public static func gridDropIndex(for point: CGPoint, frames: [Int: CGRect], count: Int) -> Int {
        for index in 0..<count {
            guard let frame = frames[index] else { continue }
            if point.y < frame.minY { return index }
            if point.y <= frame.maxY, point.x < frame.midX { return index }
        }
        return count
    }

    /// from の要素を、落とす位置 dropIndex へ移す（同じ位置なら、そのまま）
    public static func moved<T>(_ array: [T], from: Int, dropIndex: Int) -> [T] {
        guard array.indices.contains(from), (0...array.count).contains(dropIndex) else { return array }
        var result = array
        let item = result.remove(at: from)
        // 取り除いた分、後ろの位置は 1 つ前にずれる
        let destination = dropIndex > from ? dropIndex - 1 : dropIndex
        result.insert(item, at: destination)
        return result
    }

    /// 一部だけを見せている一覧で並べ替えたとき、全体の並びをどう変えるか
    ///
    /// ストリップに、いまのデスクトップのウインドウだけを見せているとき、見えている行の番号で並べ替える。
    /// 見えていないもの（ほかのデスクトップのウインドウ）の並びは崩さない。
    /// - Parameters:
    ///   - all: 全体の並び
    ///   - visible: 見えている行の並び（all の一部。順番は all と同じ）
    ///   - from: 見えている行の番号
    ///   - dropIndex: 見えている行の、落とす位置（その行の前。visible.count なら最後の行の後ろ）
    public static func movedSubset<ID: Equatable>(all: [ID], visible: [ID], from: Int, dropIndex: Int) -> [ID] {
        guard visible.indices.contains(from), (0...visible.count).contains(dropIndex),
              !isNoOp(from: from, dropIndex: dropIndex)
        else { return all }
        let moving = visible[from]
        var result = all.filter { $0 != moving }
        if dropIndex < visible.count, let anchor = result.firstIndex(of: visible[dropIndex]) {
            // 落とす位置の行の前に入れる
            result.insert(moving, at: anchor)
        } else if let last = visible.last(where: { $0 != moving }), let anchor = result.firstIndex(of: last) {
            // 最後の行の後ろに入れる
            result.insert(moving, at: anchor + 1)
        } else {
            return all
        }
        return result
    }

    /// 同じアプリをまとめているときの並べ替え（movedSubset と同じ引数）
    ///
    /// - 同じアプリのウインドウのとなりに落としたら、そのウインドウだけを動かす（アプリの中の順番を変える）
    /// - ほかのアプリの間に落としたら、同じアプリのウインドウをまとめて、その位置へ動かす
    /// 動かしたあとも、同じアプリはまとまったまま（RecentOrder.clustered）
    public static func movedSubset<ID: Equatable>(all: [ID], visible: [ID], from: Int, dropIndex: Int, clusteringBy app: (ID) -> String?) -> [ID] {
        guard visible.indices.contains(from), (0...visible.count).contains(dropIndex),
              !isNoOp(from: from, dropIndex: dropIndex)
        else { return all }
        let moving = visible[from]
        let key = app(moving)
        let next = dropIndex < visible.count ? visible[dropIndex] : nil
        let previous = dropIndex > 0 ? visible[dropIndex - 1] : nil
        let staysInApp = key != nil && (next.map(app) == key || previous.map(app) == key)
        if staysInApp {
            return RecentOrder.clustered(movedSubset(all: all, visible: visible, from: from, dropIndex: dropIndex), app: app)
        }
        // 同じアプリのウインドウをまとめて動かす（分からないものは、そのウインドウだけ）
        let block = key.map { key in all.filter { app($0) == key } } ?? [moving]
        var rest = all.filter { item in !block.contains(item) }
        if let next, let anchor = rest.firstIndex(of: next) {
            rest.insert(contentsOf: block, at: anchor)
        } else if let last = visible.last(where: { item in !block.contains(item) }), let anchor = rest.firstIndex(of: last) {
            rest.insert(contentsOf: block, at: anchor + 1)
        } else {
            return all
        }
        return RecentOrder.clustered(rest, app: app)
    }

    /// その行を含む、となり合った同じ鍵（アプリ）の行の範囲（2 つ以上つながっているときだけ。1 つだけなら nil）
    public static func cluster<Key: Equatable>(at index: Int, keys: [Key]) -> ClosedRange<Int>? {
        guard keys.indices.contains(index) else { return nil }
        let key = keys[index]
        var first = index, last = index
        while first > 0, keys[first - 1] == key { first -= 1 }
        while last + 1 < keys.count, keys[last + 1] == key { last += 1 }
        return first < last ? first...last : nil
    }

    /// 同じアプリをまとめているときに、その位置（その番号の行の前）に落とせるか。
    ///
    /// まとまりはまとめて動かすので、自分のまとまりの中・すぐ前後（動かない位置）と、
    /// ほかのアプリのまとまりの中（同じ鍵の 2 つの行の間）には落とせない
    /// - Parameter cluster: ドラッグしている行のまとまり（1 つだけの行なら nil）
    public static func canDrop<Key: Equatable>(at drop: Int, keys: [Key], cluster: ClosedRange<Int>?) -> Bool {
        if let cluster, (cluster.lowerBound...(cluster.upperBound + 1)).contains(drop) { return false }
        guard drop > 0, drop < keys.count else { return true }
        return keys[drop - 1] != keys[drop]
    }

    /// 落としても並びが変わらない位置か（自分の前・自分のすぐ後ろ）
    public static func isNoOp(from: Int, dropIndex: Int) -> Bool {
        dropIndex == from || dropIndex == from + 1
    }
}
