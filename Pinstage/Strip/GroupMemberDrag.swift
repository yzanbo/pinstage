import SwiftUI

/// ストリップの中での、ドラッグによるグループへの出し入れ（グループの行の位置と、いま重ねているグループ）
@Observable
final class GroupDropTargets {
    /// ストリップの中身全体の座標の名前（左上が原点。StripController.pointerInContent と同じ）
    nonisolated static let space = "strip.root"

    /// グループごとの行の枠
    var frames: [UUID: CGRect] = [:]
    /// グループの欄の見えている範囲（スクロールで隠れた行には落とさない）
    var viewport: CGRect = .null
    /// いま重ねているグループ（光らせる）
    var hovered: UUID?
    /// グループの見本のアイコンごとの枠（同じグループの中で並べ替えるとき、どのアイコンに重ねたかを見る）
    var memberFrames: [MemberKey: CGRect] = [:]
    /// いま重ねている、同じグループのアイコン（光らせる）
    var hoveredMember: MemberKey?

    /// その位置にあるグループ（見えている行だけ）
    func group(at point: CGPoint) -> UUID? {
        guard viewport.isNull || viewport.contains(point) else { return nil }
        return frames.first { $0.value.contains(point) }?.key
    }

    /// その位置にある、そのグループのアイコン（自分は除く）
    func member(at point: CGPoint, inGroup id: UUID, excluding index: Int) -> MemberKey? {
        memberFrames.first { $0.key.groupID == id && $0.key.index != index && $0.value.contains(point) }?.key
    }
}

/// グループの見本のアイコン 1 つ（どのグループの何番目か）
struct MemberKey: Hashable {
    let groupID: UUID
    let index: Int
}

/// 見本のアイコンをドラッグして、外す・ほかのグループへ移すための手がかり
struct MemberDragContext {
    let groupID: UUID
    let strip: StripController
    let stage: StageController
}

/// 見本のアイコンをドラッグする
///
/// - グループの行の外で離す: そのグループから外す（外へ出ている間は「−」の印を出す）
/// - ほかのグループの行の上で離す: そちらへ移す（移す先を光らせる）
/// - 同じグループのほかのアイコンの上で離す: 並び順を変える（重ねているアイコンを光らせる）
/// - 自分のグループの行の中の、それ以外のところで離す: 何もしない
/// 動かさずに離したときは、行のクリック（グループを呼び出す）になる
struct MemberDrag: ViewModifier {
    let context: MemberDragContext?
    let index: Int
    /// 同じグループのアイコンに重ねて離したとき、入れ替えるか（false なら、その位置へ差し込む）
    let swaps: Bool
    @State private var offset: CGSize = .zero
    @State private var isRemoving = false

    func body(content: Content) -> some View {
        if let context {
            let key = MemberKey(groupID: context.groupID, index: index)
            content
                // 枠は、ずらす前（offset の前）の位置で覚える
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(GroupDropTargets.space)) } action: {
                    context.strip.groupTargets.memberFrames[key] = $0
                }
                .onDisappear { context.strip.groupTargets.memberFrames[key] = nil }
                // 同じグループのほかのアイコンを、ここに重ねているとき（並べ替えの行き先）は光らせる
                .overlay {
                    if context.strip.groupTargets.hoveredMember == key {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .background(Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                            .allowsHitTesting(false)
                    }
                }
                .offset(offset)
                .zIndex(offset == .zero ? 0 : 2)
                .overlay(alignment: .topTrailing) {
                    if isRemoving {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white, .red)
                            .offset(x: offset.width + 4, y: offset.height - 4)
                    }
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .global)
                        .onChanged { value in
                            context.strip.isDragging = true
                            offset = value.translation
                            let target = target(context)
                            context.strip.groupTargets.hovered = target == context.groupID ? nil : target
                            context.strip.groupTargets.hoveredMember = target == context.groupID ? sibling(context) : nil
                            isRemoving = target == nil
                        }
                        .onEnded { _ in
                            let target = target(context)
                            let sibling = target == context.groupID ? sibling(context) : nil
                            offset = .zero
                            isRemoving = false
                            context.strip.isDragging = false
                            context.strip.groupTargets.hovered = nil
                            context.strip.groupTargets.hoveredMember = nil
                            if let target {
                                if target != context.groupID {
                                    context.stage.moveMember(at: index, from: context.groupID, to: target)
                                } else if let sibling {
                                    // 同じグループのほかのアイコンの上で離したら、並び順を変える
                                    withAnimation(.snappy(duration: 0.2)) {
                                        context.stage.reorderMember(inGroup: context.groupID, from: index, to: sibling.index, swap: swaps)
                                    }
                                }
                            } else {
                                context.stage.removeMember(at: index, fromGroup: context.groupID)
                            }
                        }
                )
                .help("同じグループのアイコンへドラッグで並び順を変える・グループの外へドラッグで外す・ほかのグループへドラッグで移す")
        } else {
            content
        }
    }

    /// いまポインタがあるグループ（なければ nil = 外す）
    private func target(_ context: MemberDragContext) -> UUID? {
        context.strip.pointerInContent().flatMap(context.strip.groupTargets.group(at:))
    }

    /// いまポインタがある、同じグループのほかのアイコン（並べ替えの行き先）
    private func sibling(_ context: MemberDragContext) -> MemberKey? {
        context.strip.pointerInContent().flatMap {
            context.strip.groupTargets.member(at: $0, inGroup: context.groupID, excluding: index)
        }
    }
}
