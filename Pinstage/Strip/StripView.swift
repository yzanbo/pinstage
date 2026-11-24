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

    /// アイコンだけの細い帯で出しているか（左右のストリップで、アイコンの並びを狭めたとき）
    private var isIconOnly: Bool { strip.isCompact }

    var body: some View {
        Group {
            if strip.isHorizontal {
                bar
            } else {
                column
            }
        }
        // グループへの出し入れで、ポインタとグループの行の位置を比べる座標
        .coordinateSpace(.named(GroupDropTargets.space))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator))
        // 幅を変えるつまみは、ステージの側の縁に出す（右のストリップなら左の縁）
        .overlay(alignment: strip.edge == .right ? .leading : .trailing) {
            // 上下のストリップの高さは、形式で決まるので、つまみは出さない
            if !strip.isHorizontal {
                ResizeEdge(strip: strip)
            }
        }
    }

    /// 左右に出したとき: 上から、帯・案内・ウインドウ・グループ・並べ方を縦に並べる
    private var column: some View {
        VStack(alignment: .leading, spacing: StripStyle.sectionSpacing) {
            StripToolbar(stage: stage, shortcuts: shortcuts, actions: actions, screen: strip.screen, compact: isIconOnly)
            if !stage.isTrusted {
                StripNotice.permission(compact: isIconOnly)
            }
            if stage.isSystemStageManagerOn, !stage.dismissedStageManagerNotice {
                StripNotice.stageManager(compact: isIconOnly) { stage.dismissedStageManagerNotice = true }
            }
            WindowSection(stage: stage, thumbnails: thumbnails, strip: strip)
            GroupSection(stage: stage, shortcuts: shortcuts, strip: strip, actions: actions)
        }
        .padding(.horizontal, isIconOnly ? 6 : 10)
        .padding(.vertical, isIconOnly ? 8 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 上下に出したとき: 左から、帯・案内・ウインドウ・グループ・並べ方を横に並べる（案内は、アイコンのボタンにする）
    private var bar: some View {
        HStack(spacing: 8) {
            StripToolbar(stage: stage, shortcuts: shortcuts, actions: actions, screen: strip.screen, compact: false, horizontal: true)
            if !stage.isTrusted {
                StripNotice.permission(compact: true).fixedSize()
            }
            if stage.isSystemStageManagerOn, !stage.dismissedStageManagerNotice {
                StripNotice.stageManager(compact: true) { stage.dismissedStageManagerNotice = true }.fixedSize()
            }
            BarDivider()
            WindowSection(stage: stage, thumbnails: thumbnails, strip: strip)
            GroupSection(stage: stage, shortcuts: shortcuts, strip: strip, actions: actions)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, StripRowSizing.barPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 横長の帯の、欄と欄の間の線
struct BarDivider: View {
    var body: some View {
        Divider().frame(height: 20)
    }
}

/// ステージの側の縁（左右のストリップ）。ドラッグしてストリップの幅を変える
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
        .pointerStyle(.frameResize(position: strip.edge == .right ? .leading : .trailing))
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
