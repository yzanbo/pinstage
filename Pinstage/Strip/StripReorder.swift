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
}

/// 一覧の並べ方（落とす位置の決め方と、落とす位置に引く線の向きが変わる）
enum ReorderLayout {
    /// 縦に並べた行（左右のストリップの一覧）
    case rows
    /// 横に並べたもの（上下のストリップ）
    case columns
    /// 格子に並べたアイコン（左右のストリップの「アイコンの並び」）
    case grid
}

/// 行をドラッグして、一覧の中なら並べ替え、ストリップの外なら onDropOutside。動かさずに離したらクリック
struct ReorderDrag: ViewModifier {
    let index: Int
    let count: Int
    let space: String
    /// 一覧の並べ方（落とす位置を、縦に並べた行なら高さ、横に並べたものなら x、格子なら縦横の位置で決める）
    var layout: ReorderLayout = .rows
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
                            let drop = switch layout {
                            case .rows: ListReorder.dropIndex(forY: value.location.y, frames: reorder.frames, count: count)
                            case .columns: ListReorder.dropIndex(forX: value.location.x, frames: reorder.frames, count: count)
                            case .grid: ListReorder.gridDropIndex(for: value.location, frames: reorder.frames, count: count)
                            }
                            reorder.dropIndex = ListReorder.isNoOp(from: index, dropIndex: drop) ? nil : drop
                        } else {
                            reorder.dropIndex = nil
                        }
                    }
                    .onEnded { value in
                        let moved = hypot(value.translation.width, value.translation.height) > Self.threshold
                        let drop = reorder.dropIndex
                        let group = moved ? hoveredGroup() : nil
                        offset = .zero
                        strip.isDragging = false
                        reorder.dropIndex = nil
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

    private var isGrid: Bool { layout != .rows }

    var body: some View {
        if let drop = reorder.dropIndex {
            if isGrid, let frame = gridLine(drop) {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: frame.height)
                    .offset(x: frame.minX - 1.5, y: frame.minY)
                    .allowsHitTesting(false)
            } else if !isGrid, let y = lineY(drop) {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 3)
                    .offset(y: y - 1.5)
                    .allowsHitTesting(false)
            }
        }
    }

    /// 横の線の高さ（落とす位置の行の上の隙間。最後なら最後の行の下）
    private func lineY(_ drop: Int) -> CGFloat? {
        if drop < count, let frame = reorder.frames[drop] { return frame.minY - 3 }
        if let last = reorder.frames[count - 1] { return last.maxY + 3 }
        return nil
    }

    /// 縦の線の位置（x と、線の上端・高さ。落とす位置のアイコンの左の隙間。最後なら最後のアイコンの右）
    private func gridLine(_ drop: Int) -> CGRect? {
        if drop < count, let frame = reorder.frames[drop] {
            return CGRect(x: frame.minX - 3, y: frame.minY, width: 0, height: frame.height)
        }
        if let last = reorder.frames[count - 1] {
            return CGRect(x: last.maxX + 3, y: last.minY, width: 0, height: last.height)
        }
        return nil
    }
}
