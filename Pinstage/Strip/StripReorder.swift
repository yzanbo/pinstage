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

    /// 行の並べ方から決める。1 列のアイコンの並びは縦に並んでいるので、一覧と同じく、上下の位置で落とす位置を決め、アイコンとアイコンの間に横の線を引く
    init(_ arrangement: RowJoin.Arrangement) {
        switch arrangement {
        case .vertical: self = .rows
        case .horizontal: self = .columns
        case .grid(let columns): self = columns > 1 ? .grid : .rows
        }
    }
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
    /// ウインドウバーから、この幅まではみ出しても並べ替えを続ける（pt）。
    /// 細い帯（アイコン 1 列）では、上下に動かしているつもりでも横に少しはみ出しやすく、はみ出すと線が消えて、離すとステージに出てしまうため
    private static let outsideTolerance: CGFloat = 24

    /// ポインタがウインドウバーの中（並べ替える範囲）にあるか。並ぶ向きと直角の側に、少しはみ出してもよい
    private var isPointerInStrip: Bool {
        let tolerance = Self.outsideTolerance
        let area = layout == .columns
            ? strip.frame.insetBy(dx: 0, dy: -tolerance)
            : strip.frame.insetBy(dx: -tolerance, dy: 0)
        return area.contains(NSEvent.mouseLocation)
    }

    /// 線を出したか・出さなかった理由を、開発用の記録に残す（実機のドラッグでしか起きない不具合を調べるため。同じ内容が続く間は書かない）
    private func trace(_ outcome: @autoclosure () -> String) {
        DesktopTrace.log("並べ替えの線", "\(space) \(layout) \(index + 1)/\(count) 枠\(reorder.frames.count) → \(outcome())")
    }

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
                            trace("グループの上")
                        } else if isPointerInStrip {
                            let target = switch layout {
                            case .rows: ListReorder.dropIndex(forY: value.location.y, frames: reorder.frames, count: count)
                            case .columns: ListReorder.dropIndex(forX: value.location.x, frames: reorder.frames, count: count)
                            case .grid: ListReorder.gridDropIndex(for: value.location, frames: reorder.frames, count: count)
                            }
                            // 落とせない位置（同じアプリをまとめているときの、まとまりの中）は、線を出さない
                            let allowed = canDrop?(target) ?? true
                            let isNoOp = ListReorder.isNoOp(from: index, dropIndex: target)
                            reorder.dropIndex = !allowed || isNoOp ? nil : target
                            trace(!allowed ? "落とせない位置 \(target)" : isNoOp ? "動かない位置 \(target)" : "線 \(target)")
                        } else {
                            reorder.dropIndex = nil
                            trace("ウインドウバーの外")
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
                        } else if !isPointerInStrip {
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
    /// 一覧の外に、線を引ける隙間（スクロールの欄の余白。いちばん上・下（左・右）の線を、行に重ねずに、その隙間に引く。0 なら一覧の内側に寄せる）
    var margin: CGFloat = 0

    /// 縦の線を引くか（横に並べたもの・格子。縦に並べた行は横の線）
    private var drawsVerticalLine: Bool { layout != .rows }

    var body: some View {
        if let drop = reorder.dropIndex {
            // 一覧の大きさ（線を一覧の内側に収めるのに使う）
            GeometryReader { geometry in
                if drawsVerticalLine, let frame = gridLine(drop, width: geometry.size.width) {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 3, height: frame.height)
                        .offset(x: frame.minX - 1.5, y: frame.minY)
                } else if !drawsVerticalLine, let y = lineY(drop, height: geometry.size.height) {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(height: 3)
                        .offset(y: y - 1.5)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// 線の太さの半分。いちばん上（左）・いちばん下（右）に落とすときも、線が見える範囲の外に出て切り取られないよう、この分だけ内側に寄せる
    private static let inset: CGFloat = 1.5
    /// いちばん上・下（左・右）の行の外に線を引くときの、行からの距離
    private static let endGap: CGFloat = 3

    /// 線を、見える範囲（一覧と、外の隙間）に収める（外に出ると、スクロールの欄に切り取られて見えない。
    /// いちばん下までスクロールしたとき、最後の行の下は欄の端になる）
    private func clamped(_ value: CGFloat, length: CGFloat) -> CGFloat {
        let lower = Self.inset - margin
        return min(max(lower, value), max(lower, length + margin - Self.inset))
    }

    /// 横の線の高さ（落とす位置の行と、前の行との間の真ん中。最初なら最初の行の上、最後なら最後の行の下）
    private func lineY(_ drop: Int, height: CGFloat) -> CGFloat? {
        if drop < count, let frame = reorder.frames[drop] {
            if drop > 0, let previous = reorder.frames[drop - 1] { return (previous.maxY + frame.minY) / 2 }
            return clamped(frame.minY - Self.endGap, length: height)
        }
        if let last = reorder.frames[count - 1] { return clamped(last.maxY + Self.endGap, length: height) }
        return nil
    }

    /// 縦の線の位置（x と、線の上端・高さ。落とす位置のアイコンと、同じ行の前のアイコンとの間の真ん中。行の左端なら左、最後なら最後のアイコンの右）
    private func gridLine(_ drop: Int, width: CGFloat) -> CGRect? {
        if drop < count, let frame = reorder.frames[drop] {
            // 前のアイコンが同じ行にあれば、その間の真ん中
            if drop > 0, let previous = reorder.frames[drop - 1], previous.maxX <= frame.minX, abs(previous.midY - frame.midY) < frame.height / 2 {
                return CGRect(x: (previous.maxX + frame.minX) / 2, y: frame.minY, width: 0, height: frame.height)
            }
            return CGRect(x: clamped(frame.minX - Self.endGap, length: width), y: frame.minY, width: 0, height: frame.height)
        }
        if let last = reorder.frames[count - 1] {
            return CGRect(x: clamped(last.maxX + Self.endGap, length: width), y: last.minY, width: 0, height: last.height)
        }
        return nil
    }
}
