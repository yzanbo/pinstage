import PinstageCore
import SwiftUI

// 同じアプリのウインドウのまとまり（ウインドウバーで、となり合った同じアプリの行を、うすい枠で囲んでつなぐ）

/// となり合った同じアプリのウインドウとのつながり（詰めて並べ、つながる側の角を小さくして、1 つの枠に見せる）
struct RowJoin {
    /// 並べる向き
    enum Axis {
        case vertical
        case horizontal
    }

    /// つなぐ行の間（pt。まとまりの枠の中）
    static let spacing: CGFloat = 2
    /// つながる側の角の丸み（pt）
    private static let joinedRadius: CGFloat = 2

    /// 前（上・左）の行と同じアプリか
    var previous = false
    /// 次（下・右）の行と同じアプリか
    var next = false
    var axis: Axis = .vertical
    /// となり合った同じアプリの行の番号の範囲（2 つ以上つながっているときだけ）
    var cluster: ClosedRange<Int>?

    init() {}

    /// - Parameters:
    ///   - index: この行の番号
    ///   - apps: 並べている行の、アプリ（WindowItem.appKey）。範囲の決め方は PinstageCore の ListReorder.cluster
    init(index: Int, apps: [String], axis: Axis) {
        cluster = ListReorder.cluster(at: index, keys: apps)
        previous = cluster.map { $0.lowerBound < index } ?? false
        next = cluster.map { $0.upperBound > index } ?? false
        self.axis = axis
    }

    /// 同じアプリのまとまりの中にあるか
    var isInCluster: Bool {
        previous || next
    }

    /// 行の形（つながる側の角だけ小さくする）
    var shape: UnevenRoundedRectangle {
        let radius = StripStyle.cornerRadius
        let before = previous ? Self.joinedRadius : radius
        let after = next ? Self.joinedRadius : radius
        return switch axis {
        case .vertical:
            UnevenRoundedRectangle(topLeadingRadius: before, bottomLeadingRadius: after, bottomTrailingRadius: after, topTrailingRadius: before, style: .continuous)
        case .horizontal:
            UnevenRoundedRectangle(topLeadingRadius: before, bottomLeadingRadius: before, bottomTrailingRadius: after, topTrailingRadius: after, style: .continuous)
        }
    }
}

/// 同じアプリのウインドウのまとまりを囲む、うすい枠（トレイ）。行ごとに、自分の分の枠を描いてつなげる
struct ClusterTray: ViewModifier {
    let join: RowJoin

    /// 枠と行の間（pt）
    static let inset: CGFloat = 3
    private static let radius: CGFloat = StripStyle.cornerRadius + inset

    func body(content: Content) -> some View {
        if join.isInCluster {
            let vertical = join.axis == .vertical
            content
                // 枠の内側の余白（前の行とは、行の間の分だけ空ける）
                .padding(vertical ? .horizontal : .vertical, Self.inset)
                .padding(vertical ? .top : .leading, join.previous ? RowJoin.spacing : Self.inset)
                .padding(vertical ? .bottom : .trailing, join.next ? 0 : Self.inset)
                .background(fillShape.fill(Color.primary.opacity(0.05)))
                .overlay(TrayOutline(previous: join.previous, next: join.next, vertical: join.axis == .vertical, radius: Self.radius).stroke(Color.primary.opacity(0.18), lineWidth: 1))
        } else {
            content
        }
    }

    /// 地の形（まとまりの両端だけ角を丸める）
    private var fillShape: UnevenRoundedRectangle {
        let before = join.previous ? 0 : Self.radius
        let after = join.next ? 0 : Self.radius
        return join.axis == .vertical
            ? UnevenRoundedRectangle(topLeadingRadius: before, bottomLeadingRadius: after, bottomTrailingRadius: after, topTrailingRadius: before)
            : UnevenRoundedRectangle(topLeadingRadius: before, bottomLeadingRadius: before, bottomTrailingRadius: after, topTrailingRadius: after)
    }
}

/// トレイの線（行と行の間には線を引かず、まとまりの外側だけを描く）
private nonisolated struct TrayOutline: Shape {
    /// 前（上・左）・次（下・右）の行と同じアプリか
    let previous: Bool
    let next: Bool
    /// 縦に並べているか
    let vertical: Bool
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        // 縦に並べるときの形で描き、横に並べるときは、縦横を入れ替えて描く
        let r = vertical ? rect.insetBy(dx: 0.5, dy: 0) : CGRect(x: rect.minY, y: rect.minX, width: rect.height, height: rect.width).insetBy(dx: 0.5, dy: 0)
        var path = Path()
        let top = previous ? 0 : radius
        let bottom = next ? 0 : radius
        // 左の辺
        path.move(to: CGPoint(x: r.minX, y: r.minY + top))
        path.addLine(to: CGPoint(x: r.minX, y: r.maxY - bottom))
        if !next {
            // 下の辺（両端の角を丸める）
            path.addArc(center: CGPoint(x: r.minX + bottom, y: r.maxY - bottom), radius: bottom, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
            path.addLine(to: CGPoint(x: r.maxX - bottom, y: r.maxY))
            path.addArc(center: CGPoint(x: r.maxX - bottom, y: r.maxY - bottom), radius: bottom, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        } else {
            path.move(to: CGPoint(x: r.maxX, y: r.maxY))
        }
        // 右の辺
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + top))
        if !previous {
            // 上の辺
            path.addArc(center: CGPoint(x: r.maxX - top, y: r.minY + top), radius: top, startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)
            path.addLine(to: CGPoint(x: r.minX + top, y: r.minY))
            path.addArc(center: CGPoint(x: r.minX + top, y: r.minY + top), radius: top, startAngle: .degrees(-90), endAngle: .degrees(-180), clockwise: true)
        }
        guard !vertical else { return path }
        // 縦横を入れ替える（x と y を入れ替える変換）
        return path.applying(CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0))
    }
}
