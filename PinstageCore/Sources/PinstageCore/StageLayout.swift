import Foundation
import CoreGraphics

/// ステージに並べるときの形（型）
public enum LayoutKind: String, CaseIterable, Codable, Sendable, Identifiable {
    /// 枚数に合わせる（3 枚までは左右に、4 枚からは格子に。最後の行が埋まらなければ、その行を広げる）
    case auto
    /// 左右に、同じ幅で並べる
    case columns
    /// 上下に、同じ高さで並べる
    case rows
    /// 2×2 に分ける（少ないときは空いた枠を空けておき、多いときは、はみ出した分を最後の枠に重ねる）
    case quarters
    /// 3×2 に分ける（決まりは 4 分割と同じ）
    case sixths
    /// 1 枚目を左に大きく、残りを右に縦に積む
    case mainLeft

    public var id: String { rawValue }

    /// メニューに出す名前
    public var title: String {
        switch self {
        case .auto: "自動（枚数に合わせる）"
        case .columns: "左右に並べる"
        case .rows: "上下に並べる"
        case .quarters: "4 分割"
        case .sixths: "6 分割"
        case .mainLeft: "左を大きく"
        }
    }

    /// 保存した値から読む。なくした型（「重ねる」）と知らない値は「自動」として読む（グループを読めなくしないため）
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LayoutKind(rawValue: raw) ?? .auto
    }
}

/// ウインドウを 1 枚だけ出すときの大きさ（用意した型のとき）
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
    /// 重ねて置くときの、1 枚の大きさ（ステージに対する割合）。登録した型の枠より多いウインドウを置くのに使う
    static let cascadeScale: CGFloat = 0.7
    /// 重ねて置くときの、ずらす量の上限（pt）
    static let cascadeMaxStep: CGFloat = 48
    /// 「左を大きく」のときの、左の 1 枚の幅（ステージに対する割合）
    static let mainLeftRatio: CGFloat = 0.6

    /// - Parameters:
    ///   - count: 並べるウインドウの数
    ///   - area: ステージの範囲
    ///   - kind: 並べ方の形
    public static func frames(count: Int, in area: CGRect, kind: LayoutKind) -> [CGRect] {
        guard count > 0, area.width > 0, area.height > 0 else { return [] }
        let cells = switch kind {
        case .auto: grid(count: count, in: area)
        case .columns: split(area, into: count, horizontally: true)
        case .rows: split(area, into: count, horizontally: false)
        case .quarters: fixedGrid(count: count, columns: 2, rows: 2, in: area)
        case .sixths: fixedGrid(count: count, columns: 3, rows: 2, in: area)
        case .mainLeft: mainLeft(count: count, in: area)
        }
        return cells.map(\.integral)
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

    /// 決まった数の枠（左上から右へ、上から下へ）。少ないときは残りの枠を空けておき、多いときは、はみ出した分を最後の枠に重ねる
    private static func fixedGrid(count: Int, columns: Int, rows: Int, in area: CGRect) -> [CGRect] {
        let width = area.width / CGFloat(columns)
        let height = area.height / CGFloat(rows)
        let last = columns * rows - 1
        return (0..<count).map { index in
            let cell = min(index, last)
            return CGRect(
                x: area.minX + CGFloat(cell % columns) * width,
                y: area.minY + CGFloat(cell / columns) * height,
                width: width,
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

    /// 重ねて置く: 同じ大きさの枠を、左上から右下へ少しずつずらす（登録した型の枠より多いウインドウを置くのに使う）
    static func cascade(count: Int, in area: CGRect) -> [CGRect] {
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

    /// 並べたウインドウが、決めた枠のとおりになっているか（アプリが大きさを丸めることがあるので、少しのずれは気にしない）
    public static func isPlaced(_ actual: CGRect, at target: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(actual.minX - target.minX) <= tolerance && abs(actual.minY - target.minY) <= tolerance
            && abs(actual.maxX - target.maxX) <= tolerance && abs(actual.maxY - target.maxY) <= tolerance
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
