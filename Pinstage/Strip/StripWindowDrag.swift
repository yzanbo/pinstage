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

/// バーのスクロール欄で切り取られないよう、見本を独立したパネルに出す。ドロップの判定は従来のドラッグに任せる。
final class StripWindowDragFeedback {
    private let dropTarget: (StripController, CGPoint) -> StripController?
    private weak var source: StripController?
    private weak var target: StripController?
    private var panel: NSPanel?

    init(dropTarget: @escaping (StripController, CGPoint) -> StripController?) {
        self.dropTarget = dropTarget
    }

    func update(from strip: StripController, pointer: CGPoint, preview: () -> StripWindowDragPreview) {
        if source !== strip {
            finish()
            source = strip
        }
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
        setTarget(dropTarget(strip, pointer))
        let screen = StageController.screen(at: pointer) ?? strip.screen
        let frame = StripDragGeometry.previewFrame(pointer: pointer, size: StripWindowDragPreview.size, in: screen.visibleFrame)
        let previewPanel: NSPanel
        if let panel {
            previewPanel = panel
        } else {
            previewPanel = makePanel(preview())
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
        setTarget(dropTarget(strip, NSEvent.mouseLocation))
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
    }

    private func setTarget(_ strip: StripController?) {
        guard target !== strip else { return }
        target?.spaceState.isWindowDropTarget = false
        target = strip
        strip?.spaceState.isWindowDropTarget = true
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
