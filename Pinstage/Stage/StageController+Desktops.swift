import AppKit
import PinstageCore

/// デスクトップ別の切り替え一覧で使う、ボタンと見出しの情報
struct DesktopListSpace: Identifiable, Equatable {
    let id: UInt64
    let name: DesktopName
    let isCurrent: Bool
    let displayName: String?

    var title: String {
        if let displayName { return "\(displayName) · \(name.title)" }
        return name.title
    }
}

extension StageController {
    /// ウインドウバーのボタンはそのディスプレイのデスクトップだけ。全体の一覧はすべてのディスプレイを含む。
    func desktopListSpaces(on screen: NSScreen, allDisplays: Bool) -> [DesktopListSpace] {
        guard isTrusted, let desktopDisplays else { return [] }
        let display = SkyLight.display(forKey: Self.displayKey(screen), in: desktopDisplays)
        let displayed = allDisplays ? desktopDisplays : display.map { [$0] } ?? []
        let displayNames = displayed.count > 1
            ? Dictionary(NSScreen.screens.map { (Self.displayKey($0), $0.localizedName) }, uniquingKeysWith: { first, _ in first })
            : [:]
        let spaces = displayed.flatMap { source in
            source.spaces.compactMap { space in
                desktopNames[space.id].map { name in
                    DesktopListSpace(id: space.id, name: name, isCurrent: source.current == space.id,
                                     displayName: displayNames[source.identifier])
                }
            }
        }
        guard allDisplays else { return spaces }
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
