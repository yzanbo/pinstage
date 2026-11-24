import AppKit
import PinstageCore
import SwiftUI

/// ストリップが置かれたデスクトップの、ウインドウの一覧。
/// ほかのデスクトップを見ている間も持ったままにする（切り替えの動きの途中から、このデスクトップの一覧が出ているように）
@Observable
final class StripSpaceState {
    /// そのデスクトップで画面に出ていたウインドウ（作ったばかりで、まだ分からないときは空）
    var windowIDs: Set<AXUIElement> = []
}

/// 1 つのディスプレイの、1 つのデスクトップのストリップ（画面の左端の、ウインドウとグループの一覧）を出す・隠す
///
/// - 常に出す: いつも出しておく（ステージはストリップの右側だけを使う）
/// - 自動で隠す: ポインタをそのディスプレイの左端に寄せたら出し、離れたら隠す
final class StripController {
    /// ストリップを出すディスプレイ
    let screen: NSScreen
    /// そのディスプレイの鍵（StageController.displayKey）
    let displayKey: String
    /// 置いたデスクトップ（非公開の API で、決めたデスクトップに置いたとき。公開の API だけのときは nil で、作ったときのデスクトップ）
    let spaceID: UInt64?
    private let panel = StripPanel()
    private let stage: StageController
    private var pointerTimer: Timer?
    /// 出しているか
    private(set) var isShown = false
    /// ストリップから行をドラッグしている途中か（その間は隠さない）
    var isDragging = false
    /// 隠していたストリップを出した（サムネイルをすぐ撮り直すため）
    var onShow: (() -> Void)?
    /// このストリップが置かれたデスクトップのウインドウの一覧
    let spaceState = StripSpaceState()

    /// このストリップが置かれたデスクトップが、いま表に出ているか
    var isOnActiveSpace: Bool {
        panel.isOnActiveSpace
    }

    /// このストリップのウインドウの番号（画面に出ているウインドウの一覧の中から、このストリップを見つける）
    var windowNumber: Int {
        panel.windowNumber
    }
    /// このストリップのデスクトップの、覚えているウインドウの一覧（いつ入ったかも覚える）
    private(set) var desktop = DesktopWindows<AXUIElement>()
    /// 作ったばかりのストリップは、次の描画まで「画面に出ているウインドウの一覧」に出てこない。
    /// この時刻までは、一覧に出ていなくても、いまのデスクトップにあるものとして扱う
    private var assumedHereUntil: TimeInterval = 0

    /// 読んだ「画面に出ているウインドウの一覧」（このアプリのウインドウの番号）の中に、このストリップが出ているか。
    /// 隠しているときも、透明にして置いてあるので出ている。ほかのデスクトップにあるときは出ていない
    func isOnScreen(in numbers: Set<Int>, at now: TimeInterval) -> Bool {
        if numbers.contains(windowNumber) {
            assumedHereUntil = 0
            return true
        }
        return now < assumedHereUntil
    }

    /// このストリップのデスクトップのウインドウを入れる（デスクトップの番号で決めたとき。変わったときだけ描き直す）
    func setWindows(_ windows: Set<AXUIElement>) {
        if spaceState.windowIDs != windows { spaceState.windowIDs = windows }
    }

    /// このストリップのデスクトップの一覧を覚える（変わったときだけ描き直す）
    func remember(_ desktop: DesktopWindows<AXUIElement>) {
        if desktop != self.desktop { self.desktop = desktop }
        if spaceState.windowIDs != desktop.windows { spaceState.windowIDs = desktop.windows }
    }

    /// このストリップに並べる候補（このデスクトップ・このディスプレイのウインドウ）。
    /// ほかのデスクトップに切り替えている間も、このデスクトップの一覧のまま
    var candidates: [WindowItem] {
        stage.spaceWindows(on: screen, spaceIDs: spaceState.windowIDs)
    }

    /// このストリップに並べるウインドウ（並べる数まで。「ほかのウインドウ」を開いていればすべて）
    var rows: [WindowItem] {
        stage.stripWindows(on: screen, spaceIDs: spaceState.windowIDs)
    }

    /// 「自動で隠す」のときに、いつ隠すか（キーで出したときは、すぐには隠さない）
    private var autoHide = StripAutoHide()
    /// ドラッグでグループに出し入れするときの、グループの行の位置
    let groupTargets = GroupDropTargets()

    init(screen: NSScreen, spaceID: UInt64? = nil, stage: StageController, thumbnails: ThumbnailStore, shortcuts: ShortcutCenter, actions: AppActions) {
        self.screen = screen
        self.spaceID = spaceID
        displayKey = StageController.displayKey(screen)
        self.stage = stage
        let view = StripView(stage: stage, thumbnails: thumbnails, shortcuts: shortcuts, strip: self, actions: actions)
        let hosting = StripHostingView(rootView: view)
        // ストリップの大きさはこちらで決める（SwiftUI の中身のいちばん小さい大きさを、ウインドウに押し付けさせない）
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    /// ストリップの枠（画面の座標）。ドラッグがストリップの外で終わったかを調べるのに使う
    var frame: CGRect {
        panel.frame
    }

    /// いまのポインタの位置（ストリップの中身の座標。左上が原点。GroupDropTargets.space と同じ）
    func pointerInContent() -> CGPoint? {
        guard let view = panel.contentView else { return nil }
        let inWindow = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let local = view.convert(inWindow, from: nil)
        return CGPoint(x: local.x, y: view.isFlipped ? local.y : view.bounds.height - local.y)
    }

    func start() {
        // いまのデスクトップに置く（隠すときも画面からは外さないので、このデスクトップに留まる）。
        // 置くデスクトップを決めてあれば、透明のまま出してから、そのデスクトップへ移す（いまのデスクトップにちらっと出ないように）
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        if let spaceID {
            SkyLight.move(windowNumber: panel.windowNumber, to: spaceID)
        }
        assumedHereUntil = ProcessInfo.processInfo.systemUptime + DesktopAttribution.newStripGrace
        placePanel(shown: stage.stripSettings.mode == .alwaysShown, animated: false)
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackPointer() }
        }
    }

    /// 閉じる（ディスプレイを外したとき・設定を変えたとき）
    func close() {
        pointerTimer?.invalidate()
        panel.orderOut(nil)
        panel.contentView = nil
    }

    /// 設定に合わせて、出す・隠す。
    /// 「自動で隠す」に変えたとき、ポインタがストリップの上にあれば（ストリップのボタンで変えたときなど）、すぐには隠さず、離れてから隠す
    func applySettings() {
        let alwaysShown = stage.stripSettings.mode == .alwaysShown
        if !alwaysShown, isShown, !StripGeometry.shouldHide(pointer: NSEvent.mouseLocation, stripFrame: panel.frame) {
            relayout()
            return
        }
        placePanel(shown: alwaysShown, animated: true)
    }

    /// 出す・隠すはそのままで、枠だけを合わせ直す（幅が変わったとき）
    func relayout() {
        placePanel(shown: isShown, animated: true)
    }

    /// キー・メニュー・自動化で出す・隠す。「自動で隠す」のとき、出したらポインタが一度入って離れるまで出したままにする
    func setShown(_ shown: Bool) {
        if shown {
            autoHide.holdOpen()
        } else {
            autoHide.reset()
        }
        placePanel(shown: shown, animated: true)
    }

    /// 自動で隠すとき、ポインタの位置で出す・隠す
    private func trackPointer() {
        guard stage.stripSettings.mode == .autoHide, !isDragging else { return }
        let pointer = NSEvent.mouseLocation
        if !isShown {
            // ポインタの位置を先に比べる（表に出ているデスクトップかを調べるのは、左端に寄せたときだけで済む）
            guard StripGeometry.shouldReveal(pointer: pointer, screenFrame: screen.frame), isOnActiveSpace else { return }
            // 左端に寄せて出したときは、ふつうの決まり（離れたら隠す）
            autoHide.reset()
            placePanel(shown: true, animated: true)
        } else {
            // ほかのデスクトップのストリップは動かさない
            guard isOnActiveSpace else { return }
            if autoHide.shouldHide(pointerNear: !StripGeometry.shouldHide(pointer: pointer, stripFrame: panel.frame)) {
                placePanel(shown: false, animated: true)
            }
        }
    }

    // MARK: - 幅を変える（右の縁のドラッグ）

    /// ドラッグしている途中の幅（ドラッグしていなければ nil）
    private var resizingWidth: CGFloat?

    /// 右の縁をドラッグしている途中。ポインタの位置に合わせて、その場で幅を変える（保存はドラッグを終えたとき）
    func resize(toPointerX x: CGFloat) {
        isDragging = true
        let width = StripGeometry.width(forPointerX: x, in: screen.visibleFrame)
        resizingWidth = width
        panel.setFrame(StripGeometry.shownFrame(in: screen.visibleFrame, width: width), display: true)
    }

    /// 右の縁のドラッグを終えた。幅を保存する（ほかのディスプレイのストリップと、ステージの並びも合わせる）
    func endResize() {
        isDragging = false
        guard let width = resizingWidth else { return }
        resizingWidth = nil
        stage.stripSettings.stripWidth = width
    }

    private func placePanel(shown: Bool, animated: Bool) {
        let wasShown = isShown
        isShown = shown
        if shown, !wasShown { onShow?() }
        let visible = screen.visibleFrame
        let width = stage.stripSettings.effectiveWidth
        let target = shown
            ? StripGeometry.shownFrame(in: visible, width: width)
            : StripGeometry.hiddenFrame(in: visible, width: width)
        // 画面から外す（orderOut）と、置いたデスクトップを忘れてしまうので、隠すときは透明にして画面の外へ置く。
        // 隠している間はクリックを素通りさせる（左隣のディスプレイの右端に重なっても、邪魔にならないように）
        panel.ignoresMouseEvents = !shown
        guard animated else {
            panel.setFrame(target, display: true)
            panel.alphaValue = shown ? 1 : 0
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = shown ? 1 : 0
        }
    }
}
