import AppKit
import PinstageCore
import SwiftUI

/// ウインドウバーの外でポインタについて動く見本。同じアプリのまとまりは、行数も表示する。
struct StripWindowDragPreview: View {
    let title: String
    let icon: NSImage?
    let count: Int

    static let size = CGSize(width: 210, height: 44)

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    Image(systemName: "macwindow").font(.system(size: 18))
                }
            }
            .frame(width: 24, height: 24)
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if count > 1 {
                Text("\(count) 枚")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.2), in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 1.5))
        .accessibilityHidden(true)
    }
}

/// ウインドウの行をドラッグするときだけの情報（ReorderDrag に渡す）
struct WindowDragInfo {
    /// バーの外で、ポインタについて動く見本
    let preview: () -> StripWindowDragPreview
    /// 別のディスプレイのウインドウバーの、その位置（行き先の行の番号）に落とせるか（行き先の行ごとの鍵 ReorderState.keys から決める。
    /// 落とせない位置には線を出さない。nil ならどこでも落とせる）
    let canDropOnOtherStrip: ((_ keys: [String], _ index: Int) -> Bool)?
    /// 別のディスプレイのウインドウバーで離した（行き先と、その一覧の落とす位置。落とせない位置・行がないときは nil）
    let onDropOnOtherStrip: (StripController, Int?) -> Void
}

/// バーのスクロール欄で切り取られないよう、見本を独立したパネルに出す。
/// 別のディスプレイのバーに重ねている間は、そのバーを光らせ、その一覧の落とす位置に線を出す
final class StripWindowDragFeedback {
    private let dropTarget: (StripController, CGPoint) -> StripController?
    private weak var source: StripController?
    private weak var target: StripController?
    private var panel: NSPanel?
    /// いまドラッグしている行の情報
    private var drag: WindowDragInfo?

    init(dropTarget: @escaping (StripController, CGPoint) -> StripController?) {
        self.dropTarget = dropTarget
    }

    func update(from strip: StripController, pointer: CGPoint, drag: WindowDragInfo) {
        if source !== strip {
            finish()
            source = strip
        }
        self.drag = drag
        // 元のバーに戻ったら、バー内で動く行だけを出す（見本を二重に出さない）。
        guard !strip.frame.contains(pointer) else {
            setTarget(nil)
            if let panel, panel.isVisible { panel.orderOut(nil) }
            return
        }
        guard strip.isShown, strip.isOnActiveSpace else {
            finish(from: strip)
            return
        }
        retarget(from: strip, at: pointer)
        let screen = StageController.screen(at: pointer) ?? strip.screen
        let frame = StripDragGeometry.previewFrame(pointer: pointer, size: StripWindowDragPreview.size, in: screen.visibleFrame)
        let previewPanel: NSPanel
        if let panel {
            previewPanel = panel
        } else {
            previewPanel = makePanel(drag.preview())
            panel = previewPanel
        }
        if previewPanel.frame.size == frame.size {
            previewPanel.setFrameOrigin(frame.origin)
        } else {
            previewPanel.setFrame(frame, display: true)
        }
        if !previewPanel.isVisible { previewPanel.orderFrontRegardless() }
    }

    /// ポインタを止めてから行き先のバーが自動で現れた場合にも、枠を光らせる。
    func refreshDropTarget(from strip: StripController) {
        guard source === strip, panel?.isVisible == true else { return }
        retarget(from: strip, at: NSEvent.mouseLocation)
    }

    /// 重ねている別のディスプレイのウインドウバーと、線を出している落とす位置（ドラッグを終えるとき、見本を消す前に聞く。線の位置にそのまま落とす）
    func destination(from strip: StripController) -> (strip: StripController, dropIndex: Int?)? {
        guard source === strip, let target else { return nil }
        return (target, target.windowReorder.dropIndex)
    }

    /// ドラッグの終了時、または元のバーを閉じたときに消す。
    func finish(from strip: StripController? = nil) {
        if let strip, source !== strip {
            if target === strip { setTarget(nil) }
            return
        }
        setTarget(nil)
        panel?.orderOut(nil)
        panel = nil
        source = nil
        drag = nil
    }

    private func setTarget(_ strip: StripController?) {
        guard target !== strip else { return }
        target?.spaceState.isWindowDropTarget = false
        target?.windowReorder.setDropIndex(nil)
        target = strip
        strip?.spaceState.isWindowDropTarget = true
    }

    /// ポインタの下の行き先のバーを光らせ、その一覧の落とす位置に線を出す（同じバーの中で並べ替えるときと同じ線）
    private func retarget(from strip: StripController, at pointer: CGPoint) {
        setTarget(dropTarget(strip, pointer))
        guard let target else { return }
        target.windowReorder.setDropIndex(dropIndex(in: target, at: pointer))
    }

    /// そのバーの一覧の、ポインタの位置での落とす位置（行がない・落とせない位置なら nil）
    private func dropIndex(in target: StripController, at pointer: CGPoint) -> Int? {
        let reorder = target.windowReorder
        guard let point = target.pointerInContent(at: pointer), let index = reorder.dropIndex(atContentPoint: point) else { return nil }
        if let canDrop = drag?.canDropOnOtherStrip, !canDrop(reorder.keys, index) { return nil }
        return index
    }

    private func makePanel(_ preview: StripWindowDragPreview) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        // ポインタに付いて動いても、下のバーへのドロップやキー入力を横取りしない。
        panel.ignoresMouseEvents = true
        let hosting = NSHostingView(rootView: preview)
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }
}
