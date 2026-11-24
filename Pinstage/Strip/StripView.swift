import AppKit
import PinstageCore
import SwiftUI

/// ストリップの中身（ウインドウの一覧・グループ・並べ方）。ストリップを出しているディスプレイのステージを操作する
struct StripView: View {
    let stage: StageController
    let thumbnails: ThumbnailStore
    let shortcuts: ShortcutCenter
    let strip: StripController
    let actions: AppActions

    private var isIconOnly: Bool { stage.stripSettings.itemSize.isIconOnly }

    var body: some View {
        VStack(alignment: .leading, spacing: StripStyle.sectionSpacing) {
            StripToolbar(stage: stage, shortcuts: shortcuts, actions: actions)
            if !stage.isTrusted {
                StripNotice.permission(compact: isIconOnly)
            }
            if stage.isSystemStageManagerOn, !stage.dismissedStageManagerNotice {
                StripNotice.stageManager(compact: isIconOnly) { stage.dismissedStageManagerNotice = true }
            }
            WindowSection(stage: stage, thumbnails: thumbnails, strip: strip)
            GroupSection(stage: stage, shortcuts: shortcuts, strip: strip, actions: actions)
            LayoutControls(stage: stage, screen: strip.screen, actions: actions)
        }
        .padding(.horizontal, isIconOnly ? 6 : 10)
        .padding(.vertical, isIconOnly ? 8 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // グループへの出し入れで、ポインタとグループの行の位置を比べる座標
        .coordinateSpace(.named(GroupDropTargets.space))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator))
        .overlay(alignment: .trailing) {
            // アイコンだけのときは幅を決めているので、幅を変えるつまみは出さない
            if !isIconOnly {
                ResizeEdge(strip: strip)
            }
        }
    }
}

/// 右の縁。ドラッグしてストリップの幅を変える
private struct ResizeEdge: View {
    let strip: StripController
    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        ZStack {
            // つかめる範囲（見えない）
            Rectangle()
                .fill(Color.clear)
                .frame(width: 10)
                .contentShape(Rectangle())
            // ポインタを乗せている間・ドラッグしている間だけ、縁を光らせる
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 3)
                .padding(.vertical, 16)
                .opacity(isHovering || isDragging ? 0.8 : 0)
        }
        .frame(maxHeight: .infinity)
        .pointerStyle(.frameResize(position: .trailing))
        .onHover { isHovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { _ in
                    isDragging = true
                    // ウインドウの幅が変わってもずれないよう、画面の座標のポインタの位置で決める
                    strip.resize(toPointerX: NSEvent.mouseLocation.x)
                }
                .onEnded { _ in
                    isDragging = false
                    strip.endResize()
                }
        )
        .help("ドラッグして幅を変える")
    }
}
