import CoreGraphics

/// グループの中身の見本（呼び出したとき、どのウインドウがどこに並ぶか）
///
/// 枠は、ステージに対する割合（0〜1。左上が原点）。並びは、グループのウインドウの順番（後ろほど前面）と同じ。
public enum GroupPreview {
    /// 見本を計算するときの、仮のステージの大きさ（よくある画面の縦横の比）
    static let referenceArea = CGRect(x: 0, y: 0, width: 1600, height: 1000)
    /// 見本を描くときの縦横の比（横 ÷ 縦）
    public static let aspectRatio = referenceArea.width / referenceArea.height
    /// 見本の 1 枚だけのときの枠（実際は大きさを変えずに前に出すので、真ん中に大きめに描く）
    static let singleSlot = UnitRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)

    /// グループを呼び出したときの並び
    /// - Parameter customLayouts: 登録した型（グループが登録した型を使うとき、ここから探す）
    public static func slots(for group: StageGroup, customLayouts: [CustomLayout]) -> [UnitRect] {
        slots(count: group.members.count, layout: group.layout, hasGap: group.hasGap, customLayouts: customLayouts)
    }

    /// - Parameters:
    ///   - count: グループのウインドウの数
    ///   - layout: グループの並べ方
    ///   - hasGap: 間を空けて並べるか（用意した型のときだけ）
    ///   - customLayouts: 登録した型
    public static func slots(count: Int, layout: LayoutChoice, hasGap: Bool, customLayouts: [CustomLayout]) -> [UnitRect] {
        guard count > 0 else { return [] }
        if count == 1, !layout.resizesSingleWindow { return [singleSlot] }
        let area = referenceArea
        // 枠は、実際に並べるときと同じ計算で決める
        let frames = layout.frames(count: count, in: area, gap: hasGap ? StageLayout.gapWidth : 0, customLayouts: customLayouts)
        return frames.map { UnitRect(frame: $0, in: area) }
    }
}
