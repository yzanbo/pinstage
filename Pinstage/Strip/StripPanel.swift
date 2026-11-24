import AppKit
import SwiftUI

/// ストリップのウインドウ
///
/// 前面のアプリからフォーカスを奪わない（nonactivatingPanel）。クリックしても Pinstage が前面にならないので、
/// ステージに出したウインドウのアプリがそのまま前面になる。
final class StripPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // ふつうのウインドウより上、「最前面に出す」ウインドウ（.floating）より 1 つ下に置く。
        // pinshot のピンなど、利用者が最前面に置いたものは、ストリップより上に出す（同じ高さだと、出した順で上下が入れ替わる）
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        // デスクトップ（操作スペース）ごとにストリップを置く。すべてのデスクトップに付いて回ると、切り替えの途中に前のデスクトップの一覧が見えてしまう。
        // .stationary は付けない（付けると、切り替えのスライドの間も画面に留まり、行き先のデスクトップの上に前の一覧が残って見える）。
        // ふつうのウインドウ（managed）にして、置いたデスクトップと一緒にスライドさせる
        collectionBehavior = [.managed, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// ストリップの中身を表示するビュー。Pinstage が前面になくても、1 回目のクリックから反応する
final class StripHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
