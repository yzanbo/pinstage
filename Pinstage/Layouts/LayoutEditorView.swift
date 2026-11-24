import AppKit
import PinstageCore
import SwiftUI

/// 型の編集画面（型の名前と、枠の位置・大きさ・前後の順番）
///
/// - 枠をドラッグで動かし、選んだ枠の角で大きさを変える。重ねても、間を空けてもよい
/// - 枠の番号は、グループのウインドウを当てはめる順番（大きい番号ほど前面）
struct LayoutEditorView: View {
    @State private var name: String
    @State private var slots: [UnitRect]
    @State private var selection: Int?
    @State private var snaps = true
    private let layoutID: UUID
    /// 画面（ステージ）の縦横の比。編集する枠の地を、実際のステージと同じ形にする
    private let aspectRatio: CGFloat
    private let onSave: (CustomLayout) -> Void
    private let onCancel: () -> Void

    init(layout: CustomLayout, aspectRatio: CGFloat, onSave: @escaping (CustomLayout) -> Void, onCancel: @escaping () -> Void) {
        _name = State(initialValue: layout.name)
        _slots = State(initialValue: layout.slots)
        _selection = State(initialValue: layout.slots.isEmpty ? nil : layout.slots.count - 1)
        layoutID = layout.id
        self.aspectRatio = aspectRatio
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var step: Double? { snaps ? LayoutEditing.gridStep : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("型の名前", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Spacer()
                Menu("ひな形から始める") {
                    ForEach(LayoutEditing.templates) { template in
                        Button(template.title) {
                            slots = template.slots
                            selection = slots.count - 1
                        }
                    }
                }
                .fixedSize()
            }

            LayoutCanvas(slots: $slots, selection: $selection, step: step)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Button {
                    slots.append(LayoutEditing.newSlot(existingCount: slots.count))
                    selection = slots.count - 1
                } label: {
                    Label("枠を足す", systemImage: "plus.rectangle")
                }
                Button {
                    guard let index = selection else { return }
                    slots.remove(at: index)
                    selection = slots.isEmpty ? nil : min(index, slots.count - 1)
                } label: {
                    Label("枠を消す", systemImage: "minus.rectangle")
                }
                .disabled(selection == nil)
                Button {
                    reorder(toFront: true)
                } label: {
                    Label("最前面へ", systemImage: "square.3.layers.3d.top.filled")
                }
                .disabled(selection == nil)
                Button {
                    reorder(toFront: false)
                } label: {
                    Label("最背面へ", systemImage: "square.3.layers.3d.bottom.filled")
                }
                .disabled(selection == nil)
                Toggle("目盛りに合わせる", isOn: $snaps)
                    .toggleStyle(.checkbox)
                Spacer()
            }
            .controlSize(.small)

            Text("枠の番号の順に、グループのウインドウを当てはめます（大きい番号ほど前面）。枠より多いウインドウは、少しずつずらして重ねます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            EditorFooter(canSave: !slots.isEmpty, onCancel: onCancel) {
                let finalName = GroupNaming.normalized(name) ?? GroupNaming.layoutPrefix
                onSave(CustomLayout(id: layoutID, name: finalName, slots: slots))
            }
        }
        .padding(16)
        .frame(width: 640)
    }

    private func reorder(toFront: Bool) {
        guard let index = selection else { return }
        let result = LayoutEditing.reordered(slots, index: index, toFront: toFront)
        slots = result.slots
        selection = result.index
    }
}

/// 枠を並べる地（ステージの形）
private struct LayoutCanvas: View {
    @Binding var slots: [UnitRect]
    @Binding var selection: Int?
    let step: Double?

    /// ドラッグを測る座標（動かない地）の名前
    static let space = "layoutCanvas"

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                // 地と目盛り
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(GridLines(step: LayoutEditing.gridStep * 2).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = nil }

                ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                    SlotView(
                        index: index,
                        slot: slot,
                        isSelected: selection == index,
                        canvasSize: size,
                        step: step,
                        onSelect: { selection = index },
                        onChange: { slots[index] = $0 }
                    )
                }
            }
            .coordinateSpace(.named(Self.space))
        }
    }
}

/// 枠 1 つ（ドラッグで動かす・選んだら角で大きさを変える）
private struct SlotView: View {
    let index: Int
    let slot: UnitRect
    let isSelected: Bool
    let canvasSize: CGSize
    let step: Double?
    let onSelect: () -> Void
    let onChange: (UnitRect) -> Void

    /// ドラッグを始めたときの枠（動かした量は、ここからの差で計算する）
    @State private var original: UnitRect?

    var body: some View {
        let frame = slot.frame(in: canvasSize)
        let color = SlotPalette.color(at: index)
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Color.accentColor : color, lineWidth: isSelected ? 2.5 : 1))
            VStack(spacing: 2) {
                Text("\(index + 1)").font(.title2.bold())
                Text("\(Int((slot.width * 100).rounded()))% × \(Int((slot.height * 100).rounded()))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .overlay {
            if isSelected {
                ForEach(LayoutEditing.Corner.allCases, id: \.self) { corner in
                    CornerHandle()
                        .position(position(of: corner, in: frame.size))
                        .gesture(resizeGesture(corner))
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(moveGesture)
        .simultaneousGesture(TapGesture().onEnded(onSelect))
        .offset(x: frame.minX, y: frame.minY)
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(LayoutCanvas.space))
            .onChanged { value in
                if original == nil {
                    original = slot
                    onSelect()
                }
                guard let original else { return }
                onChange(LayoutEditing.moved(
                    original,
                    dx: value.translation.width / canvasSize.width,
                    dy: value.translation.height / canvasSize.height,
                    step: step
                ))
            }
            .onEnded { _ in original = nil }
    }

    private func resizeGesture(_ corner: LayoutEditing.Corner) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(LayoutCanvas.space))
            .onChanged { value in
                if original == nil { original = slot }
                guard let original else { return }
                onChange(LayoutEditing.resized(
                    original,
                    corner: corner,
                    dx: value.translation.width / canvasSize.width,
                    dy: value.translation.height / canvasSize.height,
                    step: step
                ))
            }
            .onEnded { _ in original = nil }
    }

    private func position(of corner: LayoutEditing.Corner, in size: CGSize) -> CGPoint {
        switch corner {
        case .topLeft: CGPoint(x: 0, y: 0)
        case .topRight: CGPoint(x: size.width, y: 0)
        case .bottomLeft: CGPoint(x: 0, y: size.height)
        case .bottomRight: CGPoint(x: size.width, y: size.height)
        }
    }
}

/// 大きさを変える角のつまみ
private struct CornerHandle: View {
    var body: some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
            .frame(width: 12, height: 12)
            .contentShape(Rectangle().inset(by: -6))
    }
}

/// 目盛りの線
private nonisolated struct GridLines: Shape {
    let step: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var value = step
        while value < 1 - 1e-9 {
            let x = rect.minX + rect.width * value
            let y = rect.minY + rect.height * value
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            value += step
        }
        return path
    }
}
