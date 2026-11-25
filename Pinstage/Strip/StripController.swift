import AppKit
import PinstageCore
import SwiftUI

/// ストリップが置かれたデスクトップの、ウインドウの一覧。
/// ほかのデスクトップを見ている間も持ったままにする（切り替えの動きの途中から、このデスクトップの一覧が出ているように）
@Observable
final class StripSpaceState {
    /// そのデスクトップで画面に出ていたウインドウ（作ったばかりで、まだ分からないときは空）
    var windowIDs: Set<AXUIElement> = []
    /// 幅を変えるドラッグの途中の幅（ドラッグしていなければ nil）。途中でも、その幅に合う形で描く
    var resizingWidth: CGFloat?
}

/// 1 つのディスプレイの、1 つのデスクトップのストリップ（画面の端の、ウインドウとグループの一覧）を出す・隠す
///
/// 出す辺（上下左右）は設定で選ぶ。左右は縦長の帯、上下は横長の帯。
/// - 常に出す: いつも出しておく（ステージは、ストリップを除いた残りを使う）
/// - 自動で隠す: ポインタをそのディスプレイの、ストリップのある端に寄せたら出し、離れたら隠す
final class StripController {
    /// ストリップを出すディスプレイ
    let screen: NSScreen
    /// そのディスプレイの鍵（StageController.displayKey）
    let displayKey: String
    /// 置いたデスクトップ（非公開の API で、決めたデスクトップに置いたとき。公開の API だけのときは nil で、作ったときのデスクトップ）
    let spaceID: UInt64?
    private let panel = StripPanel()
    private let stage: StageController
    private let actions: AppActions
    private var pointerTimer: Timer?
    /// 出しているか
    private(set) var isShown = false
    /// ストリップから行をドラッグしている途中か（その間は隠さない）
    var isDragging = false
    /// デスクトップ一覧へポインタを動かしている間は、自動で隠さない。
    var desktopListIsOpen = false
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

    /// いま、細い帯の形（上の帯・並べ方のボタンを、アイコンだけにして縦に並べる）で出しているか。
    /// 左右のストリップで、アイコンの並びを狭めたとき（幅を変えるドラッグの途中も、その幅で決める）
    var isCompact: Bool {
        !isHorizontal && StripGeometry.usesCompactChrome(width: spaceState.resizingWidth ?? stage.stripSettings.effectiveThickness)
    }

    /// ウインドウの行の描き方（形式と、アイコンの大きさから決まる）
    var rowKind: StripRowKind {
        stage.stripSettings.rowKind
    }

    /// いまのディスプレイ（作ったときの NSScreen の値が古くならないよう、つないでいるディスプレイから同じものを探し直す）。
    /// Dock・メニューバーの設定を変えると、使える範囲（visibleFrame）が変わるため
    private var currentScreen: NSScreen {
        NSScreen.screens.first { StageController.displayKey($0) == displayKey } ?? screen
    }

    /// そのディスプレイの使える範囲（メニューバーと Dock を除いた範囲）
    var visibleFrame: CGRect {
        currentScreen.visibleFrame
    }

    /// ストリップを出す辺
    var edge: StripEdge {
        stage.stripSettings.edge
    }

    /// 横長の帯で出しているか（上・下）
    var isHorizontal: Bool {
        edge.isHorizontal
    }

    /// 前に置いたときの辺（辺を変えたときは、形が変わるので、動きを付けずに置き直す）
    private var placedEdge: StripEdge?

    /// スクロールして、いま見えている行のウインドウ（サムネイルを撮る相手を、見えている行だけにするため）
    private(set) var visibleRowIDs: Set<AXUIElement> = []

    /// 行が見えた・見えなくなった（ウインドウバーの一覧から）
    func setRowVisible(_ id: AXUIElement, _ visible: Bool) {
        if visible { visibleRowIDs.insert(id) } else { visibleRowIDs.remove(id) }
    }

    /// サムネイルを撮るウインドウ（並べたウインドウのうち、スクロールして見えている行だけ。まだ分からないときは、並べたものすべて）
    var thumbnailTargets: [WindowItem] {
        let rows = rows
        let visible = rows.filter { visibleRowIDs.contains($0.id) }
        return visible.isEmpty ? rows : visible
    }

    /// このウインドウバーに並べるウインドウ（このデスクトップ・このディスプレイのウインドウ。数で区切らない）。
    /// ほかのデスクトップに切り替えている間も、このデスクトップの一覧のまま
    var rows: [WindowItem] {
        stage.spaceWindows(on: screen, spaceIDs: spaceState.windowIDs)
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
        self.actions = actions
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

    /// SwiftUI で測ったボタンの枠（左上が原点）を、AppKit の画面座標へ移す。
    func screenRect(for rect: CGRect) -> CGRect {
        panel.convertToScreen(CGRect(x: rect.minX, y: panel.frame.height - rect.maxY,
                                     width: rect.width, height: rect.height))
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
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// 閉じる（ディスプレイを外したとき・設定を変えたとき）
    func close() {
        closeDesktopList()
        pointerTimer?.invalidate()
        panel.orderOut(nil)
        panel.contentView = nil
    }

    func closeDesktopList() {
        if desktopListIsOpen { actions.closeDesktopList(self) }
    }

    /// 設定に合わせて、出す・隠す。
    /// 「自動で隠す」に変えたとき、ポインタがストリップの上にあれば（ストリップのボタンで変えたときなど）、すぐには隠さず、離れてから隠す
    func applySettings() {
        let alwaysShown = stage.stripSettings.mode == .alwaysShown
        if !alwaysShown, isShown, isPointerNear(NSEvent.mouseLocation) {
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

    /// 0.1 秒ごとに確かめること
    private func tick() {
        finishResizeIfReleased()
        trackPointer()
    }

    /// 内側の縁のドラッグを離したのに、終わりの知らせが届かなかったとき（ドラッグの途中でストリップの形が変わると、届かないことがある）は、
    /// ここで幅を決める（決めないと、見た目の幅だけが変わり、ステージの範囲は前の幅のまま残る）
    private func finishResizeIfReleased() {
        guard spaceState.resizingWidth != nil, NSEvent.pressedMouseButtons == 0 else { return }
        DesktopTrace.log("ウインドウバーの幅", "ドラッグの終わりの知らせが届かなかったので、ここで決める")
        endResize()
    }

    /// 自動で隠すとき、ポインタの位置で出す・隠す
    private func trackPointer() {
        guard stage.stripSettings.mode == .autoHide, !isDragging, !desktopListIsOpen else { return }
        let pointer = NSEvent.mouseLocation
        if !isShown {
            // ポインタの位置を先に比べる（表に出ているデスクトップかを調べるのは、端に寄せたときだけで済む）
            guard StripGeometry.shouldReveal(pointer: pointer, screenFrame: currentScreen.frame, edge: edge), isOnActiveSpace else { return }
            // 端に寄せて出したときは、ふつうの決まり（離れたら隠す）
            autoHide.reset()
            placePanel(shown: true, animated: true)
        } else {
            // ほかのデスクトップのストリップは動かさない
            guard isOnActiveSpace else { return }
            if autoHide.shouldHide(pointerNear: isPointerNear(pointer)) {
                placePanel(shown: false, animated: true)
            }
        }
    }

    /// ポインタが、出しているストリップの近くにあるか（ストリップと画面の端との間も、近くに入れる）
    private func isPointerNear(_ pointer: CGPoint) -> Bool {
        !StripGeometry.shouldHide(pointer: pointer, stripFrame: panel.frame, screenFrame: currentScreen.frame, edge: edge)
    }

    // MARK: - 幅を変える（左右のストリップの、内側の縁のドラッグ）

    /// 内側の縁をドラッグしている途中。ポインタの位置に合わせて、その場で幅を変える（保存はドラッグを終えたとき）
    func resize(toPointerX x: CGFloat) {
        guard !isHorizontal else { return }
        isDragging = true
        let width = StripGeometry.width(forPointerX: x, in: visibleFrame, edge: edge, range: stage.stripSettings.widthRange)
        if spaceState.resizingWidth != width { spaceState.resizingWidth = width }
        panel.setFrame(StripGeometry.shownFrame(in: visibleFrame, edge: edge, thickness: width), display: true)
    }

    /// 内側の縁のドラッグを終えた。幅を保存する（ほかのディスプレイのストリップと、ステージの並びも合わせる）
    func endResize() {
        isDragging = false
        guard let width = spaceState.resizingWidth else { return }
        spaceState.resizingWidth = nil
        DesktopTrace.log("ウインドウバーの幅", "決めた: \(Int(width))")
        // いまの形式の幅として覚える（アイコンの並びの幅は、一覧・サムネイルの幅とは別）
        stage.stripSettings.width = width
    }

    private func placePanel(shown: Bool, animated: Bool) {
        if !shown { closeDesktopList() }
        let wasShown = isShown
        isShown = shown
        if shown, !wasShown { onShow?() }
        let visible = visibleFrame
        let edge = edge
        let thickness = stage.stripSettings.effectiveThickness
        let target = shown
            ? StripGeometry.shownFrame(in: visible, edge: edge, thickness: thickness)
            : StripGeometry.hiddenFrame(in: visible, edge: edge, thickness: thickness)
        // 辺を変えたときは、縦長と横長が入れ替わるので、動きを付けずに置き直す
        let movedEdge = placedEdge != nil && placedEdge != edge
        placedEdge = edge
        // 画面から外す（orderOut）と、置いたデスクトップを忘れてしまうので、隠すときは透明にして画面の外へ置く。
        // 隠している間はクリックを素通りさせる（隣のディスプレイの端に重なっても、邪魔にならないように）
        panel.ignoresMouseEvents = !shown
        guard animated, !movedEdge else {
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
