import CoreGraphics
import Foundation

/// ステージに対する割合で表した枠（0〜1。左上が原点）
///
/// 割合で覚えるので、大きさの違うディスプレイでも同じ形になる。
public struct UnitRect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// ステージの範囲の中の枠から作る（範囲の外にはみ出したところは切る）
    public init(frame: CGRect, in area: CGRect) {
        let clipped = frame.intersection(area)
        let source = clipped.isNull ? CGRect(origin: area.origin, size: .zero) : clipped
        x = Double((source.minX - area.minX) / area.width)
        y = Double((source.minY - area.minY) / area.height)
        width = Double(source.width / area.width)
        height = Double(source.height / area.height)
    }

    /// その大きさに当てはめた枠（丸めない。見本を描くとき）
    public func frame(in size: CGSize) -> CGRect {
        CGRect(x: CGFloat(x) * size.width, y: CGFloat(y) * size.height, width: CGFloat(width) * size.width, height: CGFloat(height) * size.height)
    }

    /// ステージの範囲に当てはめた枠
    public func rect(in area: CGRect) -> CGRect {
        CGRect(
            x: area.minX + CGFloat(x) * area.width,
            y: area.minY + CGFloat(y) * area.height,
            width: CGFloat(width) * area.width,
            height: CGFloat(height) * area.height
        ).integral
    }
}

/// 利用者が登録した型（並べ方の形だけ。どのアプリかは覚えない）
///
/// ぴったり分けるだけでなく、重ねたり、間を空けたりした形も覚えられる。
/// 枠の順番は前後の順番（後ろほど前面）。
public struct CustomLayout: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var slots: [UnitRect]

    public init(id: UUID = UUID(), name: String, slots: [UnitRect]) {
        self.id = id
        self.name = name
        self.slots = slots
    }

    /// ステージの範囲に当てはめる。型の枠より多いウインドウは、型の枠に入らなかった分を、少しずつずらして重ねて置く
    public func frames(count: Int, in area: CGRect) -> [CGRect] {
        Self.frames(slots: slots, count: count, in: area)
    }

    /// 枠の並びを、ステージの範囲に当てはめる（登録した型・記録した配置のどちらも同じ）
    static func frames(slots: [UnitRect], count: Int, in area: CGRect) -> [CGRect] {
        guard count > 0 else { return [] }
        let used = slots.prefix(count).map { $0.rect(in: area) }
        let rest = count - used.count
        guard rest > 0 else { return used }
        return used + StageLayout.cascade(count: rest, in: area)
    }
}

/// グループに覚えさせる並べ方（用意した型・登録した型・記録した配置）
public enum LayoutChoice: Codable, Equatable, Hashable, Sendable {
    case builtIn(LayoutKind)
    case custom(UUID)
    /// 見えている画面をそのまま記録した配置（ウインドウごとの枠。並びは重なりの順番＝後ろほど前面）
    case recorded([UnitRect])

    /// 記録した配置から、kept が false のメンバーの枠を抜く（ほかの並べ方はそのまま）
    public func keepingSlots(where kept: [Bool]) -> LayoutChoice {
        guard case .recorded(let slots) = self else { return self }
        return .recorded(slots.enumerated().compactMap { index, slot in
            index < kept.count && !kept[index] ? nil : slot
        })
    }

    /// 見えている画面の枠（後ろから前の順）から、記録した配置を作る（ステージに対する割合で覚える）
    public static func recording(_ frames: [CGRect], in stage: CGRect) -> LayoutChoice {
        .recorded(frames.map { UnitRect(frame: $0, in: stage) })
    }

    /// 記録した配置の、メニューなどに出す名前
    public static let recordedTitle = "記録した配置"

    /// 並べ方の名前（消した型は「自動」）
    public func title(customLayouts: [CustomLayout]) -> String {
        switch self {
        case .builtIn(let kind): kind.title
        case .custom(let id): customLayouts.first { $0.id == id }?.name ?? LayoutKind.auto.title
        case .recorded: Self.recordedTitle
        }
    }

    /// 1 枚だけ出すときも、型に合わせて大きさを変えるか（用意した型は、1 枚だと画面いっぱいになってしまうので、大きさを変えずに前に出す）
    public var resizesSingleWindow: Bool {
        switch self {
        case .builtIn: false
        case .custom, .recorded: true
        }
    }

    /// ステージの範囲に当てはめた、ウインドウごとの枠（実際に並べるときも、グループの見本を描くときも、ここで決める）
    /// - Parameter customLayouts: 登録した型（消した型は「自動」で並べる）
    public func frames(count: Int, in area: CGRect, customLayouts: [CustomLayout]) -> [CGRect] {
        switch self {
        case .builtIn(let kind):
            return StageLayout.frames(count: count, in: area, kind: kind)
        case .recorded(let slots):
            return CustomLayout.frames(slots: slots, count: count, in: area)
        case .custom(let id):
            guard let custom = customLayouts.first(where: { $0.id == id }) else {
                return StageLayout.frames(count: count, in: area, kind: .auto)
            }
            return custom.frames(count: count, in: area)
        }
    }
}

extension UnitRect: Hashable {}
