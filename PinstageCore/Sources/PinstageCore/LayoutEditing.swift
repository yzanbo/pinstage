/// 型の編集画面での、枠の動かし方の計算
///
/// 枠はステージに対する割合（0〜1。左上が原点）。重ねても、間を空けてもよい。
public enum LayoutEditing {
    /// 枠のいちばん小さい幅・高さ（割合）
    public static let minimumSize = 0.1
    /// 吸着するときの目盛り（割合）
    public static let gridStep = 0.05

    /// 大きさを変えるときにつかむ角
    public enum Corner: CaseIterable, Sendable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    /// 目盛りに合わせる（step が nil なら、そのまま）
    public static func snapped(_ value: Double, step: Double?) -> Double {
        guard let step, step > 0 else { return value }
        return (value / step).rounded() * step
    }

    /// 枠を動かす（ステージの外へは出さない）
    public static func moved(_ rect: UnitRect, dx: Double, dy: Double, step: Double?) -> UnitRect {
        var result = rect
        result.x = min(max(snapped(rect.x + dx, step: step), 0), 1 - rect.width)
        result.y = min(max(snapped(rect.y + dy, step: step), 0), 1 - rect.height)
        return result
    }

    /// 角をつかんで大きさを変える（反対の角は動かさない。小さくしすぎない・ステージの外へは出さない）
    public static func resized(_ rect: UnitRect, corner: Corner, dx: Double, dy: Double, step: Double?) -> UnitRect {
        var minX = rect.x
        var minY = rect.y
        var maxX = rect.x + rect.width
        var maxY = rect.y + rect.height
        switch corner {
        case .topLeft, .bottomLeft:
            minX = min(max(snapped(minX + dx, step: step), 0), maxX - minimumSize)
        case .topRight, .bottomRight:
            maxX = max(min(snapped(maxX + dx, step: step), 1), minX + minimumSize)
        }
        switch corner {
        case .topLeft, .topRight:
            minY = min(max(snapped(minY + dy, step: step), 0), maxY - minimumSize)
        case .bottomLeft, .bottomRight:
            maxY = max(min(snapped(maxY + dy, step: step), 1), minY + minimumSize)
        }
        return UnitRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 新しく足す枠（足すたびに少しずつずらして、重なっても見分けられるようにする）
    public static func newSlot(existingCount: Int) -> UnitRect {
        let offset = Double(existingCount % 6) * 0.05
        return UnitRect(x: 0.1 + offset, y: 0.1 + offset, width: 0.5, height: 0.6)
    }

    /// 前後の順番を変える（toFront なら最前面へ、そうでなければ最背面へ）。枠の番号を返す
    public static func reordered(_ slots: [UnitRect], index: Int, toFront: Bool) -> (slots: [UnitRect], index: Int) {
        guard slots.indices.contains(index) else { return (slots, index) }
        // 枠の並びは前後の順番（後ろほど前面）なので、最後へ移すと最前面になる
        return toFront
            ? (ListReorder.moved(slots, from: index, dropIndex: slots.count), slots.count - 1)
            : (ListReorder.moved(slots, from: index, dropIndex: 0), 0)
    }

    /// 編集を始めるときのひな形
    public struct Template: Sendable, Identifiable {
        public let id: String
        public let title: String
        public let slots: [UnitRect]
    }

    /// ひな形。前の 5 つは、用意した並べ方（LayoutKind）と同じ形・同じ順番・同じ名前（「自動」は枚数で形が変わるので除く）。
    /// 最後の「重ねる」は、型でしか作れない形
    public static let templates: [Template] = [
        Template(id: "columns", title: LayoutKind.columns.title, slots: [
            UnitRect(x: 0, y: 0, width: 0.5, height: 1),
            UnitRect(x: 0.5, y: 0, width: 0.5, height: 1),
        ]),
        Template(id: "rows", title: LayoutKind.rows.title, slots: [
            UnitRect(x: 0, y: 0, width: 1, height: 0.5),
            UnitRect(x: 0, y: 0.5, width: 1, height: 0.5),
        ]),
        Template(id: "quarters", title: LayoutKind.quarters.title, slots: grid(columns: 2, rows: 2)),
        Template(id: "sixths", title: LayoutKind.sixths.title, slots: grid(columns: 3, rows: 2)),
        Template(id: "mainLeft", title: LayoutKind.mainLeft.title, slots: [
            UnitRect(x: 0, y: 0, width: 0.6, height: 1),
            UnitRect(x: 0.6, y: 0, width: 0.4, height: 0.5),
            UnitRect(x: 0.6, y: 0.5, width: 0.4, height: 0.5),
        ]),
        Template(id: "overlap", title: "重ねる", slots: [
            UnitRect(x: 0.05, y: 0.08, width: 0.6, height: 0.7),
            UnitRect(x: 0.3, y: 0.2, width: 0.6, height: 0.7),
        ]),
    ]

    /// 同じ大きさの枠を、左上から右へ、上から下へ並べる
    private static func grid(columns: Int, rows: Int) -> [UnitRect] {
        let width = 1 / Double(columns), height = 1 / Double(rows)
        return (0..<(columns * rows)).map { index in
            UnitRect(x: Double(index % columns) * width, y: Double(index / columns) * height, width: width, height: height)
        }
    }
}
