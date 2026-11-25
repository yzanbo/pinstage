import AppKit
import Carbon.HIToolbox
import Observation
import PinstageCore
import SwiftUI

struct DesktopPickerSection: Identifiable {
    enum ID: Hashable { case desktop(UInt64), current, unassigned, flat }
    let id: ID
    let title: String
    let isCurrent: Bool
    let windows: [WindowItem]
    var badges: [AXUIElement: DesktopPickerBadge] = [:]

    var spaceID: UInt64? {
        if case .desktop(let id) = id { return id }
        return nil
    }

    func rowID(_ window: WindowItem) -> DesktopPickerRowID {
        DesktopPickerRowID(section: id, window: window.id)
    }
}

struct DesktopPickerBadge {
    let text: String
    let title: String
}

struct DesktopPickerRowID: Hashable {
    let section: DesktopPickerSection.ID
    let window: AXUIElement
}

@Observable
final class DesktopPickerModel {
    let stage: StageController
    let screen: NSScreen
    let thumbnails: ThumbnailStore
    /// 実際に表示する見た目（サムネイルの許可がなければ、設定上の見た目と異なる）
    private(set) var appearance: WindowSwitcherSettings.Appearance
    private(set) var columns: Int
    var selected: DesktopPickerRowID?
    /// 打った文字（ウインドウ名・アプリ名で絞り込む）
    private(set) var query = ""
    /// スペースで選んだウインドウ（↩ で、まとめてステージに並べる。選んだ順）
    private(set) var marked: [AXUIElement] = []
    var onClose: () -> Void = {}
    /// 表示（グループ分け・見た目・大きさ・絞り込み）を変えたとき（パネルを、中身に合う大きさにする）
    var onLayoutChange: () -> Void = {}
    /// この回の表示で、離したら確定する修飾キー。空なら、Enter やクリックで確定する。
    @ObservationIgnored private var release: WindowSwitcherRelease<NSEvent.ModifierFlags>

    private let focusHistory: WindowFocusHistory<AXUIElement>
    private var previewCapture: DesktopPickerThumbnails?

    /// - Parameters:
    ///   - appearance: 表示する見た目（サムネイルは、画面収録の許可がなければアイコンだけに読み替えたもの）
    ///   - desktop: 最初に選ぶデスクトップ（ウインドウバーのデスクトップのボタンから開いたとき。そのデスクトップの最初のウインドウを選ぶ）
    ///   - shortcutModifiers: ショートカットで開くときの修飾キー。確定方法にかかわらず、直前のウインドウを選ぶ。ボタンから開く場合は nil。
    init(
        stage: StageController, screen: NSScreen, thumbnails: ThumbnailStore,
        appearance: WindowSwitcherSettings.Appearance, focusing desktop: UInt64? = nil,
        shortcutModifiers: NSEvent.ModifierFlags? = nil
    ) {
        self.stage = stage
        self.screen = screen
        self.thumbnails = thumbnails
        self.appearance = appearance
        release = WindowSwitcherRelease(confirmation: stage.windowSwitcherSettings.confirmation, shortcutModifiers: shortcutModifiers)
        focusHistory = stage.windowFocusHistory
        columns = WindowSwitcherLayout.columns(
            for: appearance, size: stage.windowSwitcherSettings.displaySize,
            panelWidth: WindowSwitcherLayout.overviewWidth(for: appearance, visibleWidth: screen.visibleFrame.width)
        )
        previewCapture = appearance == .thumbnails ? DesktopPickerThumbnails(thumbnails: thumbnails) : nil
        if let desktop {
            selectDesktop(desktop)
        } else if shortcutModifiers != nil {
            selectPrevious()
        }
    }

    /// そのデスクトップの最初のウインドウを選ぶ（デスクトップ別ならその見出しの最初、まとめて表示なら、そのデスクトップにある最初のもの）。
    /// ウインドウがなければ、ふつうに開いたときと同じ（先頭）
    private func selectDesktop(_ desktop: UInt64) {
        let visibleSections = sections
        let membership = stage.windowSpaces ?? [:]
        selected = Self.firstRow(in: visibleSections.filter { $0.spaceID == desktop }) { _ in true }
            ?? Self.firstRow(in: visibleSections) { membership[$0.id]?.contains(desktop) == true }
    }

    /// 直前に使っていたウインドウ（いま前にあるウインドウの、1 つ前）を選ぶ。なければ先頭
    private func selectPrevious() {
        let open = stage.windows.map(\.id)
        let recent = focusHistory.ordered(open)
        guard recent.count > 1 else { return }
        select(recent[1])
    }

    /// 設定で選んでいる見た目（サムネイルは、画面収録の許可がない間、アイコンだけで表示する）
    var preferredAppearance: WindowSwitcherSettings.Appearance {
        stage.windowSwitcherSettings.appearance
    }

    var grouping: WindowSwitcherSettings.Grouping {
        stage.windowSwitcherSettings.grouping
    }

    var displaySize: WindowSwitcherSettings.DisplaySize {
        stage.windowSwitcherSettings.displaySize
    }

    var confirmation: WindowSwitcherSettings.Confirmation {
        stage.windowSwitcherSettings.confirmation
    }

    var isWaitingForModifierRelease: Bool { release.isWaiting }

    /// サムネイルを選んでいるのに、画面収録の許可がないため、アイコンだけで表示しているか
    var isMissingThumbnailPermission: Bool {
        preferredAppearance == .thumbnails && appearance != .thumbnails
    }

    /// グループ分けを変える（設定にも残す。選んでいるウインドウはそのまま）
    func setGrouping(_ grouping: WindowSwitcherSettings.Grouping) {
        guard grouping != self.grouping else { return }
        let window = selectedWindow?.id
        stage.windowSwitcherSettings.grouping = grouping
        relayout(preserving: window)
    }

    /// 見た目を変える（設定にも残す。選んでいるウインドウはそのまま）。
    /// サムネイルは画面収録の許可が要るので、なければ求め、許可が出るまではアイコンだけで表示する
    func setAppearance(_ preferred: WindowSwitcherSettings.Appearance) {
        let window = selectedWindow?.id
        let shown = stage.setWindowSwitcherAppearance(preferred, thumbnails: thumbnails)
        guard shown != appearance else { return }
        appearance = shown
        previewCapture?.finish()
        previewCapture = shown == .thumbnails ? DesktopPickerThumbnails(thumbnails: thumbnails) : nil
        relayout(preserving: window)
    }

    /// グループや表示中のウインドウを変えず、大きさと列数だけを合わせ直す。
    func setDisplaySize(_ size: WindowSwitcherSettings.DisplaySize) {
        guard size != displaySize else { return }
        stage.windowSwitcherSettings.displaySize = size
        onLayoutChange()
    }

    func setConfirmation(_ confirmation: WindowSwitcherSettings.Confirmation) {
        guard confirmation != self.confirmation else { return }
        stage.windowSwitcherSettings.confirmation = confirmation
        // Enter に変えたら今の自動確定を止める。自動確定を有効にするのは次にショートカットで開いたとき。
        release.cancel()
    }

    /// 絞り込みの文字を変える（合うものの最初を選ぶ）
    private func setQuery(_ query: String) {
        guard query != self.query else { return }
        self.query = query
        selected = nil
        onLayoutChange()
    }

    /// 一覧の大きさ（幅は見た目と画面の幅で決め、高さは中身に合わせる。決まりは PinstageCore の WindowSwitcherLayout）。
    /// 格子の列の数も、この幅に合わせる（矢印キーで動く列の数も同じ値を使う）
    func fitOverview(in visible: CGRect) -> CGSize {
        let width = WindowSwitcherLayout.overviewWidth(for: appearance, visibleWidth: visible.width)
        columns = WindowSwitcherLayout.columns(for: appearance, size: displaySize, panelWidth: width)
        let sections = sections
        let height = WindowSwitcherLayout.overviewHeight(
            for: appearance, size: displaySize, sectionCounts: sections.map(\.windows.count),
            titledSections: sections.contains { !$0.title.isEmpty }, columns: columns,
            maximumHeight: (visible.height * WindowSwitcherLayout.maximumHeightShare).rounded(.down),
            showsNotice: isMissingThumbnailPermission
        )
        return CGSize(width: width, height: height)
    }

    func panelFrame() -> CGRect {
        let visible = screen.visibleFrame
        return WindowSwitcherLayout.panelFrame(size: fitOverview(in: visible), in: visible)
    }

    private func relayout(preserving window: AXUIElement?) {
        onLayoutChange()
        select(window)
    }

    /// 表示を変えたあとも、同じウインドウを選んだままにする（グループ分けが変わると、行の番号も変わるので探し直す）
    private func select(_ window: AXUIElement?) {
        guard let window, let row = Self.firstRow(in: sections, where: { $0.id == window }) else { return }
        selected = row
    }

    private static func firstRow(in sections: [DesktopPickerSection], where matches: (WindowItem) -> Bool) -> DesktopPickerRowID? {
        for section in sections {
            if let window = section.windows.first(where: matches) { return section.rowID(window) }
        }
        return nil
    }

    // MARK: - 選んだウインドウの印

    /// ステージに出しているウインドウか（どのディスプレイのステージでも）
    func isOnStage(_ window: WindowItem) -> Bool {
        NSScreen.screens.contains { stage.stage(on: $0).selection.contains(window.id) }
    }

    /// スペースで選んでいるか
    func isMarked(_ window: WindowItem) -> Bool {
        marked.contains(window.id)
    }

    /// 選んでいるウインドウを、まとめて並べる候補に入れる・外す。
    /// ほかのアプリのウインドウを、いまのデスクトップへ連れてくることはできないので、いまのデスクトップのウインドウだけ選べる
    private func toggleMark(_ window: WindowItem) {
        if let index = marked.firstIndex(of: window.id) {
            marked.remove(at: index)
        } else if stage.currentSpaceIDs.contains(window.id) {
            marked.append(window.id)
        } else {
            NSSound.beep()
        }
    }

    var sections: [DesktopPickerSection] {
        guard stage.isTrusted else { return [] }
        let filter = WindowSwitcherFilter(query: query)
        let windows = stage.windows.filter {
            !stage.hiddenWindowIDs.contains($0.id) && filter.matches(title: $0.title, appName: $0.appName)
        }
        // すべてのディスプレイのデスクトップ（開いたディスプレイのいまのデスクトップが先頭）
        let spaces = stage.desktopListSpaces(on: screen, forSwitcher: true)
        if grouping == .byDesktop, spaces.isEmpty {
            // デスクトップを見分けられない場合、分かる範囲だけを出す。
            let (here, other) = (
                windows.filter { stage.currentSpaceIDs.contains($0.id) },
                windows.filter { !stage.currentSpaceIDs.contains($0.id) }
            )
            return [DesktopPickerSection(id: .current, title: "現在のデスクトップ", isCurrent: true, windows: here)]
                + unassignedSection(other)
        }
        let ids = windows.map(\.id)
        let items = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let membership = stage.windowSpaces ?? [:]
        if grouping == .flat {
            return [flatSection(focusHistory.ordered(ids).compactMap { items[$0] }, spaces: spaces, membership: membership)]
        }
        let index = DesktopWindowList(windows: ids, membership: membership, desktops: Set(spaces.map(\.id)))
        let known = spaces.map { space in
            DesktopPickerSection(id: .desktop(space.id), title: space.title, isCurrent: space.isCurrent,
                                 windows: (index.byDesktop[space.id] ?? []).compactMap { items[$0] })
        }
        // 絞り込んでいる間は、合うもののないデスクトップを出さない
        let shown = query.isEmpty ? known : known.filter { !$0.windows.isEmpty }
        return shown + unassignedSection(index.unassigned.compactMap { items[$0] })
    }

    /// まとめて表示するときは、複数のデスクトップにあるウインドウも一度だけ出す。
    private func flatSection(
        _ ordered: [WindowItem], spaces: [DesktopListSpace], membership: [AXUIElement: Set<UInt64>]
    ) -> DesktopPickerSection {
        let current = Set(spaces.filter(\.isCurrent).map(\.id))
        var badges: [AXUIElement: DesktopPickerBadge] = [:]
        for window in ordered {
            let known = membership[window.id, default: []]
            if !known.isDisjoint(with: current) { continue }
            if let space = spaces.first(where: { known.contains($0.id) }) {
                badges[window.id] = DesktopPickerBadge(text: space.name.number.map(String.init) ?? "全画面", title: space.title)
            } else if !stage.currentSpaceIDs.contains(window.id) {
                badges[window.id] = DesktopPickerBadge(text: "不明", title: "デスクトップ不明")
            }
        }
        return DesktopPickerSection(id: .flat, title: "", isCurrent: false, windows: ordered, badges: badges)
    }

    private func unassignedSection(_ windows: [WindowItem]) -> [DesktopPickerSection] {
        guard !windows.isEmpty else { return [] }
        return [DesktopPickerSection(id: .unassigned, title: "デスクトップ不明", isCurrent: false, windows: windows)]
    }

    private func position(in sections: [DesktopPickerSection]) -> WindowSwitcherNavigation.Position? {
        if let selected, let section = sections.firstIndex(where: { $0.id == selected.section }),
           let item = sections[section].windows.firstIndex(where: { $0.id == selected.window }) {
            return .init(section: section, item: item)
        }
        return sections.firstIndex(where: { !$0.windows.isEmpty }).map { .init(section: $0, item: 0) }
    }

    func selectedItem(in sections: [DesktopPickerSection]) -> (DesktopPickerSection, WindowItem)? {
        guard let position = position(in: sections) else { return nil }
        let section = sections[position.section]
        return (section, section.windows[position.item])
    }

    private var selectedWindow: WindowItem? { selectedItem(in: sections)?.1 }

    func activate(_ window: WindowItem, in section: DesktopPickerSection) {
        onClose()
        stage.focusFromDesktopList(window.id, on: section.spaceID)
    }

    /// 決める（↩・修飾キーを離したとき）。スペースで選んだウインドウがあれば、まとめてステージに並べる。なければ、選んでいるウインドウに切り替える
    func confirm() {
        let items = marked.compactMap(stage.item(for:))
        if !items.isEmpty {
            onClose()
            stage.present(items, on: screen)
        } else if let (section, window) = selectedItem(in: sections) {
            activate(window, in: section)
        } else {
            onClose()
        }
    }

    /// Tab（forward）・⇧Tab で、並びの順に 1 つ進める・戻す（最後の次は最初）
    func step(forward: Bool) {
        let sections = sections
        guard let next = WindowSwitcherNavigation.stepping(
            from: position(in: sections), forward: forward, counts: sections.map { $0.windows.count }
        ) else { return }
        select(next, in: sections)
    }

    /// 修飾キーが変わった（ショートカットで開いたとき、押していた修飾キーをすべて離したら決める）
    func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        guard release.consumeIfReleased(flags) else { return }
        confirm()
    }

    func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        let control = event.modifierFlags.contains(.control)
        switch Int(event.keyCode) {
        case kVK_Escape:
            // 絞り込み・選んだものを先に消し、何もなければ閉じる
            if !query.isEmpty {
                setQuery("")
            } else if !marked.isEmpty {
                marked = []
            } else {
                onClose()
            }
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            confirm()
            return true
        case kVK_Tab:
            step(forward: !event.modifierFlags.contains(.shift))
            return true
        case kVK_Space where !command && !control:
            if let window = selectedWindow { toggleMark(window) }
            return true
        case kVK_Delete:
            if !query.isEmpty { setQuery(String(query.dropLast())) }
            return true
        case kVK_ANSI_G where command:
            setGrouping(grouping.toggled)
            return true
        case kVK_ANSI_W where command:
            if let window = selectedWindow { stage.close(window) }
            return true
        case kVK_ANSI_Q where command:
            if let window = selectedWindow { stage.quitApp(of: window) }
            return true
        case kVK_ANSI_M where command:
            if let window = selectedWindow { stage.minimize(window) }
            return true
        case let key where command && Self.numberKeys.prefix(3).contains(key):
            // ⌘1 一覧・⌘2 アイコンだけ・⌘3 サムネイル
            let number = (Self.numberKeys.firstIndex(of: key) ?? 0) + 1
            if let appearance = WindowSwitcherSettings.Appearance(shortcutNumber: number) { setAppearance(appearance) }
            return true
        case let key where !command && !control && query.isEmpty && grouping == .byDesktop && Self.numberKeys.contains(key):
            // 数字キー: そのデスクトップの見出しの最初へ（絞り込んでいないとき）
            jump(toSection: (Self.numberKeys.firstIndex(of: key) ?? 0))
            return true
        case kVK_UpArrow: move(.up)
        case kVK_DownArrow: move(.down)
        case kVK_LeftArrow: move(.left)
        case kVK_RightArrow: move(.right)
        default:
            // 文字は絞り込みに足す（⌘・⌃ との組み合わせは除く）
            guard !command, !control, let characters = event.charactersIgnoringModifiers,
                  let first = characters.unicodeScalars.first, !CharacterSet.controlCharacters.contains(first)
            else { return false }
            setQuery(query + characters)
            return true
        }
        return true
    }

    /// 矢印キーで動かす（格子では、上下は同じ列を優先する）
    private func move(_ direction: WindowSwitcherNavigation.Direction) {
        let sections = sections
        guard let position = position(in: sections) else { return }
        let next = WindowSwitcherNavigation.moving(
            from: position, direction, counts: sections.map { $0.windows.count }, columns: columns
        )
        select(next, in: sections)
    }

    private func select(_ position: WindowSwitcherNavigation.Position, in sections: [DesktopPickerSection]) {
        let section = sections[position.section]
        selected = section.rowID(section.windows[position.item])
    }

    /// 見出しの数字と数字キーの行き先を、同じ一覧から決める。
    func numberedDesktops(in sections: [DesktopPickerSection]) -> [DesktopPickerSection] {
        guard grouping == .byDesktop, query.isEmpty else { return [] }
        return Array(sections.filter { $0.spaceID != nil }.prefix(Self.numberKeys.count))
    }

    /// その番号（0 から）のデスクトップの最初のウインドウへ（ウインドウのないデスクトップは選べない）
    private func jump(toSection index: Int) {
        let sections = numberedDesktops(in: sections)
        guard sections.indices.contains(index), let window = sections[index].windows.first else { return }
        selected = sections[index].rowID(window)
    }

    /// 数字のキー（1〜9。⌘1〜3 は見た目、数字だけならデスクトップへ移る）
    private static let numberKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                     kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    func setPreviewVisible(_ row: DesktopPickerRowID, window: WindowItem, _ visible: Bool) {
        previewCapture?.setVisible(row, window: window, visible)
    }

    func finish() {
        release.cancel()
        previewCapture?.finish()
    }
}

/// ウインドウバーのボタンとショートカットで、同じ一覧を別の場所に出す。
final class DesktopPickerController: NSObject, NSWindowDelegate {
    private let stage: StageController
    private let thumbnails: ThumbnailStore
    private var panel: KeyboardPanel?
    private var activeModel: DesktopPickerModel?
    private weak var sourceStrip: StripController?
    private var localClick: Any?
    private var globalClick: Any?

    init(stage: StageController, thumbnails: ThumbnailStore) {
        self.stage = stage
        self.thumbnails = thumbnails
    }

    /// ショートカット（⌥Tab）で開く。ポインタのあるディスプレイの真ん中に出す。
    /// 直前に使っていたウインドウを選んで開く。すでにショートカットで開いていれば、確定方法にかかわらず次へ進む。
    func openFromShortcut(modifiers: NSEvent.ModifierFlags) {
        if sourceStrip == nil, let model = activeModel {
            model.step(forward: true)
            return
        }
        guard let screen = StageController.screenUnderPointer else { return }
        // コールバックが届く前にキーを離しても確定できるよう、現在の状態でなく登録した修飾キーを渡す。
        show(on: screen, shortcutModifiers: modifiers)
    }

    /// ウインドウバーのデスクトップのボタンから開く。⌥Tab と同じ画面を、そのウインドウバーのディスプレイの真ん中に出す
    /// - Parameter desktop: 最初に選ぶデスクトップ（nil ならまとめボタン。先頭を選ぶ）
    func show(desktop: UInt64?, from strip: StripController) {
        guard stage.stripSettings.showsDesktopList, strip.isShown, strip.isOnActiveSpace else { return }
        show(on: strip.screen, focusing: desktop, from: strip)
    }

    /// 切り替え画面を、そのディスプレイの真ん中に出す（大きさは中身に合わせ、表示を変えたら合わせ直す）
    /// - Parameter strip: 開いたウインドウバー（開いている間、自動で隠さない）
    /// - Parameter shortcutModifiers: ショートカットで開いたときの修飾キー。ボタンから開く場合は nil。
    private func show(
        on screen: NSScreen, focusing desktop: UInt64? = nil, from strip: StripController? = nil,
        shortcutModifiers: NSEvent.ModifierFlags? = nil
    ) {
        let appearance = thumbnails.windowSwitcherAppearance(stage.windowSwitcherSettings.appearance)
        let model = DesktopPickerModel(stage: stage, screen: screen, thumbnails: thumbnails, appearance: appearance,
                                       focusing: desktop, shortcutModifiers: shortcutModifiers)
        let frame = model.panelFrame()
        guard frame.width > 0, frame.height > 0 else { return }
        close()
        let panel = KeyboardPanel()
        let hosting = StripHostingView(rootView: DesktopPickerView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.keyHandler = { model.handleKey($0) }
        panel.flagsHandler = { model.handleFlagsChanged($0) }
        panel.setFrame(frame, display: true)
        panel.delegate = self
        model.onClose = { [weak self] in self?.close() }
        // 画面の中で表示を変えたら、パネルを中身に合う大きさにする（画面の真ん中のまま）
        model.onLayoutChange = { [weak self, weak model] in
            guard let self, let model, let panel = self.panel, self.activeModel === model else { return }
            panel.setFrame(model.panelFrame(), display: true, animate: true)
        }
        sourceStrip = strip
        strip?.windowSwitcherIsOpen = true
        activeModel = model
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        watchOutsideClicks()
        // 出すまでの間に修飾キーを離していたら（すばやく ⌥Tab を押して離したとき）、すぐ決める（1 つ前のウインドウに戻る）
        if model.isWaitingForModifierRelease {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak model] in
                model?.handleFlagsChanged(NSEvent.modifierFlags)
            }
        }
    }

    /// 一覧をキーにしないウインドウ（ストリップなど）を押した場合も、一覧の外なら閉じる。
    private func watchOutsideClicks() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClick = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            if let self, event.window !== panel { close() }
            return event
        }
        globalClick = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close(openedFrom strip: StripController? = nil) {
        if let strip, sourceStrip !== strip { return }
        guard let panel else { return }
        self.panel = nil
        activeModel?.finish()
        activeModel = nil
        sourceStrip?.windowSwitcherIsOpen = false
        sourceStrip = nil
        if let localClick { NSEvent.removeMonitor(localClick) }
        if let globalClick { NSEvent.removeMonitor(globalClick) }
        localClick = nil
        globalClick = nil
        panel.delegate = nil
        panel.orderOut(nil)
        // クリックの処理の途中でも閉じられるよう、中身を手放すのは次の処理に任せる。
        DispatchQueue.main.async {
            panel.contentView = nil
            panel.keyHandler = nil
            panel.flagsHandler = nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === panel { close() }
    }

    #if DEBUG
    /// 見本に描く一覧と、その大きさ（本物と同じく中身に合わせる）
    /// - Parameter desktop: 最初に選ぶデスクトップ（ウインドウバーのボタンから開いたとき）
    static func preview(
        stage: StageController, screen: NSScreen, focusing desktop: UInt64? = nil,
        appearance: WindowSwitcherSettings.Appearance = .icons
    ) -> (view: some View, size: CGSize) {
        let model = DesktopPickerModel(stage: stage, screen: screen, thumbnails: ThumbnailStore(),
                                       appearance: appearance, focusing: desktop)
        let size = model.fitOverview(in: CGRect(x: 0, y: 0, width: 1600, height: 1000))
        // 見本に実際の画面は撮らない。撮れないときのアイコンと名前を描く。
        model.finish()
        return (DesktopPickerView(model: model), size)
    }
    #endif
}
