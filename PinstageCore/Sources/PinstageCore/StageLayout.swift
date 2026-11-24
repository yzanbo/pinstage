import Foundation
import CoreGraphics

/// ステージに並べるときの形（型）
public enum LayoutKind: String, CaseIterable, Codable, Sendable, Identifiable {
    /// 均等に並べる（2〜3 枚は横に、4 枚からは格子に）
    case auto
    /// 1 枚目を左に大きく、残りを右に縦に積む
    case mainLeft
    /// 上下に積む
    case rows
    /// 少しずつずらして重ねる
    case cascade

    public var id: String { rawValue }

    /// メニューに出す名前
    public var title: String {
        switch self {
        case .auto: "自動（均等）"
        case .mainLeft: "左を大きく"
        case .rows: "上下に並べる"
        case .cascade: "重ねる"
        }
    }

    /// 1 枚だけ出すときも、型に合わせて大きさを変えるか。
    /// 均等などは 1 枚だと画面いっぱいになってしまうので、大きさはそのままにして前に出すだけにする
    public var resizesSingleWindow: Bool {
        self == .cascade
    }
}

/// ウインドウを 1 枚だけ出すときの大きさ（用意した型のうち「重ねる」以外のとき）
public enum SingleWindowSize: String, CaseIterable, Codable, Sendable, Identifiable {
    /// 大きさを変えない（ストリップと重なるところだけ中へ入れる）
    case keep
    /// 縦はステージいっぱい、横幅はそのまま
    case fullHeight
    /// ステージいっぱい
    case fill

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .keep: "そのまま"
        case .fullHeight: "縦いっぱい（幅はそのまま）"
        case .fill: "ステージいっぱい"
        }
    }

    public static let `default` = SingleWindowSize.fullHeight
    private static let key = "stage.singleWindowSize"

    public init(defaults: UserDefaults) {
        self = defaults.string(forKey: Self.key).flatMap(SingleWindowSize.init(rawValue:)) ?? .default
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.key)
    }
}

/// ステージの範囲に、ウインドウの枠を割り当てる計算
///
/// 座標は左上が原点で、下へ行くほど y が大きい（アクセシビリティの API と同じ向き）。
/// 返す配列の順番は、ステージに出す順番（後ろほど前面）と同じ。
public enum StageLayout {
    /// 「余白を空ける」のときの、間の幅（pt）
    public static let gapWidth: CGFloat = 16
    /// 「重ねる」のときの、1 枚の大きさ（ステージに対する割合）
    static let cascadeScale: CGFloat = 0.7
    /// 「重ねる」のときの、ずらす量の上限（pt）
    static let cascadeMaxStep: CGFloat = 48
    /// 「左を大きく」のときの、左の 1 枚の幅（ステージに対する割合）
    static let mainLeftRatio: CGFloat = 0.6

    /// - Parameters:
    ///   - count: 並べるウインドウの数
    ///   - area: ステージの範囲
    ///   - kind: 並べ方の形
    ///   - gap: ウインドウ同士の間と、ステージの端との間（0 ならぴったり）
    public static func frames(count: Int, in area: CGRect, kind: LayoutKind, gap: CGFloat = 0) -> [CGRect] {
        guard count > 0, area.width > 0, area.height > 0 else { return [] }
        // ステージの端を gap/2 だけ内側にし、各枠も gap/2 ずつ内側にすると、間も端も gap になる
        let half = max(0, gap) / 2
        let inner = area.insetBy(dx: half, dy: half)
        let cells: [CGRect]
        switch kind {
        case .auto: cells = grid(count: count, in: inner)
        case .mainLeft: cells = mainLeft(count: count, in: inner)
        case .rows: cells = split(inner, into: count, horizontally: false)
        case .cascade: return cascade(count: count, in: area.insetBy(dx: max(0, gap), dy: max(0, gap)))
        }
        return cells.map { $0.insetBy(dx: half, dy: half).integral }
    }

    /// 均等: 3 枚までは横に並べ、4 枚からは格子にする（列の数は √n を切り上げ）
    private static func grid(count: Int, in area: CGRect) -> [CGRect] {
        if count <= 3 { return split(area, into: count, horizontally: true) }
        let columns = Int(Double(count).squareRoot().rounded(.up))
        let rows = Int((Double(count) / Double(columns)).rounded(.up))
        let width = area.width / CGFloat(columns)
        let height = area.height / CGFloat(rows)
        return (0..<count).map { index in
            let row = index / columns
            let column = index % columns
            // 最後の行が埋まらないときは、その行の枠を横に広げて余りを作らない
            let inLastRow = row == rows - 1
            let lastRowCount = count - columns * (rows - 1)
            let rowColumns = inLastRow ? lastRowCount : columns
            let rowWidth = area.width / CGFloat(rowColumns)
            return CGRect(
                x: area.minX + CGFloat(column) * (inLastRow ? rowWidth : width),
                y: area.minY + CGFloat(row) * height,
                width: inLastRow ? rowWidth : width,
                height: height
            )
        }
    }

    /// 左を大きく: 1 枚目を左に、残りを右に縦に積む
    private static func mainLeft(count: Int, in area: CGRect) -> [CGRect] {
        guard count > 1 else { return [area] }
        let leftWidth = area.width * mainLeftRatio
        let left = CGRect(x: area.minX, y: area.minY, width: leftWidth, height: area.height)
        let right = CGRect(x: area.minX + leftWidth, y: area.minY, width: area.width - leftWidth, height: area.height)
        return [left] + split(right, into: count - 1, horizontally: false)
    }

    /// 重ねる: 同じ大きさの枠を、左上から右下へ少しずつずらす
    private static func cascade(count: Int, in area: CGRect) -> [CGRect] {
        let size = CGSize(width: area.width * cascadeScale, height: area.height * cascadeScale)
        guard count > 1 else {
            // 1 枚なら真ん中に置く
            return [CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height).integral]
        }
        let room = CGSize(width: area.width - size.width, height: area.height - size.height)
        let stepX = min(cascadeMaxStep, room.width / CGFloat(count - 1))
        let stepY = min(cascadeMaxStep, room.height / CGFloat(count - 1))
        return (0..<count).map { index in
            CGRect(
                x: area.minX + stepX * CGFloat(index),
                y: area.minY + stepY * CGFloat(index),
                width: size.width,
                height: size.height
            ).integral
        }
    }

    /// 範囲を同じ大きさに分ける（horizontally が true なら左から右へ、false なら上から下へ）
    private static func split(_ area: CGRect, into count: Int, horizontally: Bool) -> [CGRect] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            if horizontally {
                let width = area.width / CGFloat(count)
                return CGRect(x: area.minX + width * CGFloat(index), y: area.minY, width: width, height: area.height)
            } else {
                let height = area.height / CGFloat(count)
                return CGRect(x: area.minX, y: area.minY + height * CGFloat(index), width: area.width, height: height)
            }
        }
    }

    /// 1 枚だけ前に出すときの枠
    public static func singleFrame(current: CGRect, in area: CGRect, size: SingleWindowSize) -> CGRect {
        switch size {
        case .keep:
            return fit(current, into: area)
        case .fullHeight:
            // 縦はいっぱいにして、横はいまの幅と位置のまま（はみ出したところだけ中へ入れる）
            let tall = CGRect(x: current.minX, y: area.minY, width: current.width, height: area.height)
            return fit(tall, into: area)
        case .fill:
            return area
        }
    }

    /// 1 枚だけ前に出すとき、大きさは変えずに、ステージの範囲からはみ出したところだけ中へ入れる
    public static func fit(_ frame: CGRect, into area: CGRect) -> CGRect {
        var result = frame
        result.size.width = min(frame.width, area.width)
        result.size.height = min(frame.height, area.height)
        result.origin.x = min(max(frame.minX, area.minX), area.maxX - result.width)
        result.origin.y = min(max(frame.minY, area.minY), area.maxY - result.height)
        return result
    }
}
