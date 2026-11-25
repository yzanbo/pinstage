import AppKit
import PinstageCore

/// デスクトップ別の切り替え一覧で使う、ボタンと見出しの情報
struct DesktopListSpace: Identifiable, Equatable {
    let id: UInt64
    let name: DesktopName
    let isCurrent: Bool
    let displayName: String?
    /// 複数画面のデスクトップを一つのバーに出すとき、短いボタンでも所属を区別する番号。
    let displayNumber: Int?

    var title: String {
        if let displayNumber {
            return "\(displayName ?? "ディスプレイ \(displayNumber)") · \(name.title)"
        }
        return name.title
    }

    var helpTitle: String { isCurrent ? "\(title)（現在）" : title }
}

extension StageController {
    /// 設定画面とスイッチャー内の切り替えで、保存と画面収録の許可の扱いをそろえる。
    @discardableResult
    func setWindowSwitcherAppearance(
        _ preferred: WindowSwitcherSettings.Appearance, thumbnails: ThumbnailStore
    ) -> WindowSwitcherSettings.Appearance {
        let changed = windowSwitcherSettings.appearance != preferred
        if changed { windowSwitcherSettings.appearance = preferred }
        return thumbnails.windowSwitcherAppearance(preferred, requestsPermission: changed)
    }

    /// ウインドウバーはその画面のデスクトップ順。メインにだけ出す設定とショートカットでは、全画面を含む。
    func desktopListSpaces(on screen: NSScreen, forSwitcher: Bool = false) -> [DesktopListSpace] {
        guard isTrusted, let desktopDisplays else { return [] }
        let display = SkyLight.display(forKey: Self.displayKey(screen), in: desktopDisplays)
        let allDisplays = forSwitcher || stripSettings.displays == .mainOnly
        let displayed = allDisplays ? desktopDisplays : display.map { [$0] } ?? []
        let displayNames = displayed.count > 1
            ? Dictionary(NSScreen.screens.map { (Self.displayKey($0), $0.localizedName) }, uniquingKeysWith: { first, _ in first })
            : [:]
        let nameCounts = Dictionary(grouping: displayNames.values, by: { $0 }).mapValues(\.count)
        let spaces = displayed.enumerated().flatMap { index, source in
            let displayName = displayNames[source.identifier].map { name in
                (nameCounts[name] ?? 0) > 1 ? "\(name)（\(index + 1)）" : name
            }
            return source.spaces.compactMap { space in
                desktopNames[space.id].map { name in
                    DesktopListSpace(id: space.id, name: name, isCurrent: source.current == space.id,
                                     displayName: displayName,
                                     displayNumber: displayed.count > 1 ? index + 1 : nil)
                }
            }
        }
        guard forSwitcher else { return spaces }
        return DesktopWindowList<AXUIElement>.puttingCurrentFirst(spaces, current: display?.current, id: \.id)
    }

    /// 並べ替えずに、選んだウインドウをそのデスクトップで前に出す。
    /// 割り当てが変わった・閉じたなどで行き先がなくなっていれば、そのまま。
    func focusFromDesktopList(_ id: AXUIElement, on desktop: UInt64?) {
        guard isTrusted, let item = item(for: id), !hiddenWindowIDs.contains(id),
              AXWindow.isValid(id) else { return }
        if let desktop, windowSpaces?[id]?.contains(desktop) != true { return }
        AXWindow.prepareToShow(id, pid: item.pid)
        raiseWindow(item)
        // 外から前に出したときと同じように、実際のフォーカスに青い枠だけを合わせる。
        scheduleFocusSync()
    }
}
