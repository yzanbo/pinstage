import AppKit
import PinstageCore
import SwiftUI

/// グループの見本（呼び出したときの並び。枠ごとに、入るアプリのアイコンを描く）
struct GroupMap: View {
    let slots: [UnitRect]
    let members: [WindowSignature]
    let running: Set<String>
    /// ストリップでは、アイコンをドラッグして外す・移すことができる（編集画面の見本では nil）
    var memberDrag: MemberDragContext?

    var body: some View {
        GeometryReader { proxy in
            // 実際の画面と同じ横長の地を、行の幅に合わせて真ん中に置く
            let height = min(proxy.size.height, proxy.size.width / GroupPreview.aspectRatio)
            let width = height * GroupPreview.aspectRatio
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
                ForEach(Array(zip(slots, members).enumerated()), id: \.offset) { index, pair in
                    let frame = pair.0.frame(in: CGSize(width: width, height: height))
                    SlotTile(index: index, member: pair.1, isRunning: running.contains(pair.1.bundleID))
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .modifier(MemberDrag(context: memberDrag, index: index, swaps: true))
                }
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 見本の枠 1 つ（入るアプリのアイコン。起動していなければ薄く描く）
private struct SlotTile: View {
    let index: Int
    let member: WindowSignature
    let isRunning: Bool

    var body: some View {
        GeometryReader { proxy in
            let color = SlotPalette.color(at: index)
            let iconSize = max(8, min(28, min(proxy.size.width, proxy.size.height) * 0.6))
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.22))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(color.opacity(0.8), lineWidth: 1))
                MemberIcon(bundleID: member.bundleID, size: iconSize, isRunning: isRunning)
            }
        }
    }
}

/// 枠の番号ごとの色（グループの見本と、型の編集画面で、同じ番号を同じ色にする）
enum SlotPalette {
    private static let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .yellow, .red]

    static func color(at index: Int) -> Color {
        colors[index % colors.count]
    }
}
