import AppKit
import PinstageCore
import SwiftUI

/// 一覧の並べ替えの途中の状態（行の枠と、どこへ落とそうとしているか）
@Observable
final class ReorderState {
    /// ウインドウの一覧・グループの一覧の座標の名前
    static let windowSpace = "strip.windows"
    static let groupSpace = "strip.groups"

    /// 行の番号ごとの枠（一覧の座標）
    var frames: [Int: CGRect] = [:]
    /// 落とす位置（その番号の行の前。並びが変わらない位置なら nil）
    var dropIndex: Int?
    /// ドラッグしている行について一緒に動く行の番号（同じアプリをまとめて動かしている間。ドラッグしている行は含まない）
    var followers: Set<Int> = []
    /// 一緒に動く行の、ずらす量（ドラッグしている行と同じ）
    var followOffset: CGSize = .zero
}

/// 一覧の並べ方（落とす位置の決め方と、落とす位置に引く線の向きが変わる）
enum ReorderLayout {
    /// 縦に並べた行（左右のウインドウバーの一覧）
    case rows
    /// 横に並べたもの（上下のウインドウバー）
    case columns
    /// 格子に並べたアイコン（左右のウインドウバーの「アイコンの並び」）
    case grid
}

/// 行をドラッグして、一覧の中なら並べ替え、ストリップの外なら onDropOutside。動かさずに離したらクリック
struct ReorderDrag: ViewModifier {
    let index: Int
    let count: Int
    let space: String
    /// 一覧の並べ方（落とす位置を、縦に並べた行なら高さ、横に並べたものなら x、格子なら縦横の位置で決める）
    var layout: ReorderLayout = .rows
    /// 同じアプリの行の番号の範囲（同じアプリをまとめているときだけ）。ドラッグしている間は、範囲の行も一緒に動かす
    var cluster: ClosedRange<Int>?
    /// その位置に落とせるか（落とせない位置には線を出さず、離しても動かさない。nil ならどこでも落とせる）
    var canDrop: ((Int) -> Bool)?
    let reorder: ReorderState
    let strip: StripController
    let onTap: () -> Void
    let onMove: (Int) -> Void
    var onDropOutside: (() -> Void)?
    /// グループの行の上で離した（ウインドウの行だけ。nil ならグループには入れない）
    var onDropOnGroup: ((UUID) -> Void)?
    @State private var offset: CGSize = .zero

    /// いま重ねているグループ（グループに入れられるときだけ）
    private func hoveredGroup() -> UUID? {
        guard onDropOnGroup != nil, let point = strip.pointerInContent() else { return nil }
        return strip.groupTargets.group(at: point)
    }

    /// これより動かしたらドラッグ（それより小さければクリック）
    private static let threshold: CGFloat = 4

    func body(content: Content) -> some View {
        content
            // 枠は、ずらす前（offset の前）の位置で覚える
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { reorder.frames[index] = $0 }
            .offset(offset)
            .zIndex(offset == .zero ? 0 : 1)
            .opacity(offset == .zero ? 1 : 0.85)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                    .onChanged { value in
                        guard hypot(value.translation.width, value.translation.height) > Self.threshold else { return }
                        strip.isDragging = true
                        offset = value.translation
                        let group = hoveredGroup()
                        if onDropOnGroup != nil { strip.groupTargets.hovered = group }
                        if group != nil {
                            // グループの上では、並べ替えの線を出さない
                            reorder.dropIndex = nil
                        } else if strip.frame.contains(NSEvent.mouseLocation) {
                            let target = switch layout {
                            case .rows: ListReorder.dropIndex(forY: value.location.y, frames: reorder.frames, count: count)
                            case .columns: ListReorder.dropIndex(forX: value.location.x, frames: reorder.frames, count: count)
                            case .grid: ListReorder.gridDropIndex(for: value.location, frames: reorder.frames, count: count)
                            }
                            // 落とせない位置（同じアプリをまとめているときの、まとまりの中）は、線を出さない
                            let allowed = canDrop?(target) ?? true
                            reorder.dropIndex = !allowed || ListReorder.isNoOp(from: index, dropIndex: target) ? nil : target
                        } else {
                            reorder.dropIndex = nil
                        }
                        // 同じアプリのまとまりは、ドラッグしている間ずっと、まとめて動かす
                        if let cluster, cluster.count > 1 {
                            reorder.followers = Set(cluster).subtracting([index])
                            reorder.followOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        let moved = hypot(value.translation.width, value.translation.height) > Self.threshold
                        let drop = reorder.dropIndex
                        let group = moved ? hoveredGroup() : nil
                        offset = .zero
                        strip.isDragging = false
                        reorder.dropIndex = nil
                        reorder.followers = []
                        reorder.followOffset = .zero
                        if onDropOnGroup != nil { strip.groupTargets.hovered = nil }
                        if !moved {
                            onTap()
                        } else if let group {
                            onDropOnGroup?(group)
                        } else if !strip.frame.contains(NSEvent.mouseLocation) {
                            onDropOutside?()
                        } else if let drop {
                            withAnimation(.snappy(duration: 0.2)) { onMove(drop) }
                        }
                    }
            )
    }
}

/// 落とす位置に引く線（縦に並べた行では行の間に横の線、横に並べたもの・格子ではその左に縦の線）
struct DropLine: View {
    let reorder: ReorderState
    let count: Int
    var layout: ReorderLayout = .rows

    /// 縦の線を引くか（横に並べたもの・格子。縦に並べた行は横の線）
    private var drawsVerticalLine: Bool { layout != .rows }

    var body: some View {
        if let drop = reorder.dropIndex {
            if drawsVerticalLine, let frame = gridLine(drop) {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: frame.height)
                    .offset(x: frame.minX - 1.5, y: frame.minY)
                    .allowsHitTesting(false)
            } else if !drawsVerticalLine, let y = lineY(drop) {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 3)
                    .offset(y: y - 1.5)
                    .allowsHitTesting(false)
            }
        }
    }

    /// 線の太さの半分。いちばん上（左）に落とすときも、線が一覧の外に出て切り取られないよう、この分だけ内側に寄せる
    private static let inset: CGFloat = 1.5

    /// 横の線の高さ（落とす位置の行の上の隙間。最後なら最後の行の下）
    private func lineY(_ drop: Int) -> CGFloat? {
        // いちばん上の行の上は一覧の端なので、隙間の代わりに一覧の内側に引く（外に出ると、スクロールの欄に切り取られて見えない）
        if drop < count, let frame = reorder.frames[drop] { return max(Self.inset, frame.minY - 3) }
        if let last = reorder.frames[count - 1] { return last.maxY + 3 }
        return nil
    }

    /// 縦の線の位置（x と、線の上端・高さ。落とす位置のアイコンの左の隙間。最後なら最後のアイコンの右）
    private func gridLine(_ drop: Int) -> CGRect? {
        if drop < count, let frame = reorder.frames[drop] {
            // いちばん左のアイコンの左も、一覧の内側に引く
            return CGRect(x: max(Self.inset, frame.minX - 3), y: frame.minY, width: 0, height: frame.height)
        }
        if let last = reorder.frames[count - 1] {
            return CGRect(x: last.maxX + 3, y: last.minY, width: 0, height: last.height)
        }
        return nil
    }
}
