import CoreGraphics

/// ストリップを出す辺（画面の上下左右）
///
/// 左右は縦長の帯（幅をドラッグで変えられる）、上下は横長の帯（高さは形式で決まる）。
public enum StripEdge: String, CaseIterable, Codable, Sendable, Identifiable {
    case left
    case right
    case top
    case bottom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .left: "左"
        case .right: "右"
        case .top: "上"
        case .bottom: "下"
        }
    }

    /// 横長の帯で出すか（上・下）
    public var isHorizontal: Bool {
        self == .top || self == .bottom
    }

    /// メニューやボタンに出す印
    public var symbolName: String {
        switch self {
        case .left: "sidebar.left"
        case .right: "sidebar.right"
        case .top: "rectangle.topthird.inset.filled"
        case .bottom: "rectangle.bottomthird.inset.filled"
        }
    }

    /// 画面座標（左下が原点）での、この辺（CGRect.divided で使う）
    var rectEdge: CGRectEdge {
        switch self {
        case .left: .minXEdge
        case .right: .maxXEdge
        case .top: .maxYEdge
        case .bottom: .minYEdge
        }
    }

    /// 画面座標での、画面の外へ向かう向き（隠すときに動かす向き）
    var outward: CGVector {
        switch self {
        case .left: CGVector(dx: -1, dy: 0)
        case .right: CGVector(dx: 1, dy: 0)
        case .top: CGVector(dx: 0, dy: 1)
        case .bottom: CGVector(dx: 0, dy: -1)
        }
    }

    /// 枠の、この辺の側の端から、外の枠の同じ辺までの距離（画面座標）
    func distance(from inner: CGRect, toEdgeOf outer: CGRect) -> CGFloat {
        switch self {
        case .left: inner.minX - outer.minX
        case .right: outer.maxX - inner.maxX
        case .top: outer.maxY - inner.maxY
        case .bottom: inner.minY - outer.minY
        }
    }

    /// 点から、枠のこの辺までの距離（画面座標。内側が正）
    func distance(from point: CGPoint, toEdgeOf frame: CGRect) -> CGFloat {
        distance(from: CGRect(origin: point, size: .zero), toEdgeOf: frame)
    }
}


/// ストリップと同じ辺にある、macOS の帯（Dock・メニューバー）との重なり
///
/// 常に出ている Dock・メニューバーは、使える範囲（visibleFrame）から除かれているので、ストリップはその内側に並び、重ならない。
/// 自動で隠れる設定のものは除かれていないので、出てきたときにストリップの上に重なる（Dock もメニューバーも、ストリップより手前に出る）。
public enum StripEdgeConflict: Equatable, Sendable {
    /// 同じ辺に、自動で隠れる Dock がある
    case autoHidingDock
    /// 上の辺で、メニューバーが自動で隠れる
    case autoHidingMenuBar

    /// Dock の位置の設定（com.apple.dock の orientation。「left」「bottom」「right」。なければ下）を、辺に読み替える
    public static func dockEdge(orientation: String?) -> StripEdge {
        switch orientation {
        case "left": .left
        case "right": .right
        default: .bottom
        }
    }

    /// その辺に置いたストリップに重なるもの（なければ nil）
    public static func conflict(edge: StripEdge, dockEdge: StripEdge, dockAutoHides: Bool, menuBarAutoHides: Bool) -> StripEdgeConflict? {
        if dockAutoHides, edge == dockEdge { return .autoHidingDock }
        if menuBarAutoHides, edge == .top { return .autoHidingMenuBar }
        return nil
    }
}
