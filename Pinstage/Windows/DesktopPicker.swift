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
    /// nil ならショートカットで開いた一覧（すべてのデスクトップ）。
    let desktop: UInt64?
    let grouping: WindowSwitcherSettings.Grouping
    let appearance: WindowSwitcherSettings.Appearance
    let columns: Int
    var selected: DesktopPickerRowID?
    var onClose: () -> Void = {}

    private let focusHistory: WindowFocusHistory<AXUIElement>
    private let previewCapture: DesktopPickerThumbnails?

    init(
        stage: StageController, screen: NSScreen, desktop: UInt64?, thumbnails: ThumbnailStore,
        appearance: WindowSwitcherSettings.Appearance = .list, panelWidth: CGFloat = 0
    ) {
        self.stage = stage
        self.screen = screen
        self.desktop = desktop
        self.thumbnails = thumbnails
        self.appearance = desktop == nil ? appearance : .list
        grouping = desktop == nil ? stage.windowSwitcherSettings.grouping : .byDesktop
        focusHistory = stage.windowFocusHistory
        columns = WindowSwitcherLayout.columns(for: self.appearance, panelWidth: panelWidth)
        previewCapture = self.appearance == .thumbnails ? DesktopPickerThumbnails(thumbnails: thumbnails) : nil
    }

    var sections: [DesktopPickerSection] {
        guard stage.isTrusted else { return [] }
        let windows = stage.windows.filter { !stage.hiddenWindowIDs.contains($0.id) }
        var spaces = stage.desktopListSpaces(on: screen, allDisplays: desktop == nil)
        if grouping == .flat { return [flatSection(windows, spaces: spaces)] }
        if let desktop { spaces = spaces.filter { $0.id == desktop } }
        if spaces.isEmpty, desktop == nil {
            // デスクトップを見分けられない場合、分かる範囲だけを出す。
            let (here, other) = (
                windows.filter { stage.currentSpaceIDs.contains($0.id) },
                windows.filter { !stage.currentSpaceIDs.contains($0.id) }
            )
            return [DesktopPickerSection(id: .current, title: "現在のデスクトップ", isCurrent: true, windows: here)]
                + unassignedSection(other)
        }
        let index = DesktopWindowList(
            windows: windows.map(\.id), membership: stage.windowSpaces ?? [:], desktops: Set(spaces.map(\.id))
        )
        let items = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = spaces.map { space in
            DesktopPickerSection(id: .desktop(space.id), title: space.title, isCurrent: space.isCurrent,
                                 windows: (index.byDesktop[space.id] ?? []).compactMap { items[$0] })
        }
        return known + (desktop == nil ? unassignedSection(index.unassigned.compactMap { items[$0] }) : [])
    }

    /// まとめて表示するときは、複数のデスクトップにあるウインドウも一度だけ出す。
    private func flatSection(_ windows: [WindowItem], spaces: [DesktopListSpace]) -> DesktopPickerSection {
        let items = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = focusHistory.ordered(windows.map(\.id)).compactMap { items[$0] }
        let membership = stage.windowSpaces ?? [:]
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

    func activate(_ window: WindowItem, in section: DesktopPickerSection) {
        onClose()
        stage.focusFromDesktopList(window.id, on: section.spaceID)
    }

    func handleKey(_ event: NSEvent) -> Bool {
        let direction: WindowSwitcherNavigation.Direction
        switch Int(event.keyCode) {
        case kVK_Escape:
            onClose()
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let (section, window) = selectedItem(in: sections) { activate(window, in: section) }
            return true
        case kVK_UpArrow: direction = .up
        case kVK_DownArrow: direction = .down
        case kVK_LeftArrow: direction = .left
        case kVK_RightArrow: direction = .right
        default: return false
        }
        let sections = sections
        guard let position = position(in: sections) else { return true }
        let next = WindowSwitcherNavigation.moving(
            from: position, direction, counts: sections.map { $0.windows.count }, columns: columns
        )
        let section = sections[next.section]
        selected = section.rowID(section.windows[next.item])
        return true
    }

    func setPreviewVisible(_ row: DesktopPickerRowID, window: WindowItem, _ visible: Bool) {
        previewCapture?.setVisible(row, window: window, visible)
    }

    func finish() {
        previewCapture?.finish()
    }
}

/// ウインドウバーのボタンとショートカットで、同じ一覧を別の場所に出す。
final class DesktopPickerController: NSObject, NSWindowDelegate {
    private let stage: StageController
    private let thumbnails: ThumbnailStore
    private var panel: KeyboardPanel?
    private var activeModel: DesktopPickerModel?
    private weak var anchorStrip: StripController?
    private var localClick: Any?
    private var globalClick: Any?

    init(stage: StageController, thumbnails: ThumbnailStore) {
        self.stage = stage
        self.thumbnails = thumbnails
    }

    func toggleOverview() {
        if panel != nil, anchorStrip == nil {
            close()
            return
        }
        guard let screen = StageController.screenUnderPointer else { return }
        let preferred = stage.windowSwitcherSettings.appearance
        if preferred == .thumbnails { thumbnails.refreshPermission() }
        let appearance = preferred.displayed(hasScreenCapturePermission: thumbnails.hasPermission)
        let frame = DesktopListGeometry.panel(size: WindowSwitcherLayout.overviewSize(for: appearance), in: screen.visibleFrame)
        let model = DesktopPickerModel(stage: stage, screen: screen, desktop: nil, thumbnails: thumbnails,
                                       appearance: appearance, panelWidth: frame.width)
        show(model, frame: frame)
    }

    func show(desktop: UInt64, anchor: CGRect, strip: StripController) {
        guard stage.stripSettings.showsDesktopList, strip.isShown, strip.isOnActiveSpace,
              stage.desktopListSpaces(on: strip.screen, allDisplays: false).contains(where: { $0.id == desktop }) else { return }
        let model = DesktopPickerModel(stage: stage, screen: strip.screen, desktop: desktop, thumbnails: thumbnails)
        let count = model.sections.first?.windows.count ?? 0
        let height = min(440, max(144, 49 + 40 * CGFloat(count)))
        let frame = DesktopListGeometry.panel(
            size: CGSize(width: 320, height: height), in: strip.visibleFrame,
            anchor: anchor, bar: strip.frame, edge: strip.edge
        )
        let attachment = DesktopPickerAttachment(edge: strip.edge, anchor: anchor, panel: frame)
        show(model, frame: frame, anchoredTo: strip, attachment: attachment)
    }

    private func show(
        _ model: DesktopPickerModel, frame: CGRect, anchoredTo strip: StripController? = nil,
        attachment: DesktopPickerAttachment? = nil
    ) {
        guard frame.width > 0, frame.height > 0 else { return }
        close()
        let panel = KeyboardPanel()
        let hosting = StripHostingView(rootView: DesktopPickerView(model: model, attachment: attachment))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.keyHandler = { model.handleKey($0) }
        panel.setFrame(frame, display: true)
        panel.delegate = self
        model.onClose = { [weak self] in self?.close() }
        anchorStrip = strip
        strip?.desktopListIsOpen = true
        activeModel = model
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        watchOutsideClicks()
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

    func close(anchoredTo strip: StripController? = nil) {
        if let strip, anchorStrip !== strip { return }
        guard let panel else { return }
        self.panel = nil
        activeModel?.finish()
        activeModel = nil
        anchorStrip?.desktopListIsOpen = false
        anchorStrip = nil
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
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === panel { close() }
    }

    #if DEBUG
    static func preview(
        stage: StageController, screen: NSScreen, desktop: UInt64?, size: CGSize,
        appearance: WindowSwitcherSettings.Appearance = .list
    ) -> some View {
        let attachment = desktop.map { _ in
            DesktopPickerAttachment(edge: .left, anchor: CGRect(x: -26, y: size.height - 58, width: 24, height: 24),
                                    panel: CGRect(origin: .zero, size: size))
        }
        let model = DesktopPickerModel(stage: stage, screen: screen, desktop: desktop, thumbnails: ThumbnailStore(),
                                       appearance: appearance, panelWidth: size.width)
        // 見本に実際の画面は撮らない。撮れないときのアイコンと名前を描く。
        model.finish()
        return DesktopPickerView(model: model, attachment: attachment)
    }
    #endif
}
