import AppKit
import Observation
import PinstageCore
import SwiftUI

/// 検索で選べるもの
enum SearchTarget: Hashable {
    case group(UUID)
    case window(AXUIElement)
}

/// 検索の欄の中身（打った言葉・選んでいる行・選んだときにすること）
@Observable
final class SearchModel {
    /// 打った言葉（変えたら、選んでいる行を先頭に戻す）
    var query = "" {
        didSet { selectedTarget = nil }
    }
    /// 選んでいるもの（nil なら先頭）。番号で覚えると、開いている間にウインドウが増減したとき、違うものを指してしまう
    var selectedTarget: SearchTarget?

    /// 選んでいる行の番号（選んでいたものがなくなっていたら先頭）
    var selected: Int {
        selectedIndex(in: results)
    }

    private func selectedIndex(in results: [SearchItem<SearchTarget>]) -> Int {
        selectedTarget.flatMap { target in results.firstIndex { $0.id == target } } ?? 0
    }

    @ObservationIgnored let stage: StageController
    /// 出す先（検索の欄を開いたときに、ポインタがあったディスプレイ）
    @ObservationIgnored let screen: NSScreen
    @ObservationIgnored var onClose: () -> Void = {}

    init(stage: StageController, screen: NSScreen) {
        self.stage = stage
        self.screen = screen
    }

    /// 絞り込んだ結果（グループ → ウインドウの順に渡し、合い方で並べ直す）
    var results: [SearchItem<SearchTarget>] {
        let groups = stage.library.groups.map { group in
            SearchItem(
                id: SearchTarget.group(group.id),
                title: group.name,
                subtitle: group.members.map { AppIcons.name(for: $0.bundleID) }.joined(separator: "・")
            )
        }
        let windows = stage.windows.map { window in
            SearchItem(id: SearchTarget.window(window.id), title: window.displayTitle, subtitle: window.appName)
        }
        return SearchMatcher.results(query: query, items: groups + windows)
    }

    /// 選ぶ行を動かす（端で止める）
    func move(_ delta: Int) {
        let results = self.results
        guard !results.isEmpty else { return }
        let index = min(max(selectedIndex(in: results) + delta, 0), results.count - 1)
        selectedTarget = results[index].id
    }

    /// 選んだものを出す（ウインドウはそれだけを出し、add なら足す。グループは呼び出す）
    func activate(at index: Int? = nil, add: Bool = false) {
        let results = self.results
        let index = index ?? selectedIndex(in: results)
        guard results.indices.contains(index) else { return }
        let target = results[index].id
        onClose()
        switch target {
        case .group(let id):
            guard let group = stage.library.group(id: id) else { return }
            let screen = self.screen
            Task { await stage.recall(group, fallback: screen) }
        case .window(let id):
            guard let item = stage.item(for: id) else { return }
            if add {
                stage.add(item, on: screen)
            } else {
                stage.showOnly(item, on: screen)
            }
        }
    }

    /// 検索の欄で押したキー（受け取ったら true）。↑↓ で選び、↩ で出し、⌘↩ で足し、esc で閉じる
    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 125: // ↓
            move(1)
        case 126: // ↑
            move(-1)
        case 36, 76: // ↩・テンキーの enter
            activate(add: event.modifierFlags.contains(.command))
        case 53: // esc
            onClose()
        default:
            return false
        }
        return true
    }
}

/// 検索の欄のウインドウ
///
/// 前面のアプリからフォーカスを奪わず（nonactivatingPanel）、文字は打てるようにキーウインドウにはなる。
/// ↑↓・↩・esc は、文字の欄に渡る前に受け取る。
final class SearchPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        // 日本語入力で変換している途中（下線が出ている間）は、↩ で確定・↑↓ で候補を選ぶので、日本語入力に任せる
        let isComposing = (firstResponder as? NSTextView)?.hasMarkedText() ?? false
        if event.type == .keyDown, !isComposing, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

/// 検索の欄を出す・閉じる（ショートカット・ストリップの🔍・メニューバーから）
final class SearchController: NSObject, NSWindowDelegate {
    private let stage: StageController
    private var panel: SearchPanel?

    /// 検索の欄の大きさ
    static let size = CGSize(width: 600, height: 420)

    init(stage: StageController) {
        self.stage = stage
    }

    /// 出していれば閉じ、出していなければ出す
    func toggle() {
        if panel != nil {
            close()
        } else {
            show()
        }
    }

    func show() {
        close()
        guard let screen = StageController.screenUnderPointer else { return }
        stage.refresh()
        let model = SearchModel(stage: stage, screen: screen)
        model.onClose = { [weak self] in self?.close() }

        let panel = SearchPanel()
        panel.keyHandler = { event in model.handleKey(event) }
        panel.contentView = NSHostingView(rootView: SearchView(model: model))
        panel.delegate = self
        // ポインタのあるディスプレイの、真ん中より少し上に出す（Spotlight と同じくらい）
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: visible.midX - Self.size.width / 2,
            y: visible.minY + visible.height * 0.62 - Self.size.height / 2
        )
        panel.setFrame(CGRect(origin: origin, size: Self.size), display: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        panel.orderOut(nil)
        // ↩・クリックの処理の途中で呼ばれるので、中身を手放すのは、その処理を終えてから
        DispatchQueue.main.async {
            panel.contentView = nil
        }
    }

    /// ほかをクリックしたら閉じる
    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}
