import AppKit
import PinstageCore

/// グループの保存と編集
///
/// グループの中身（StageGroup.Content）は、いまのステージから作るか、見えている画面を記録して作る。
/// 新しいグループにするのも、前からあるグループを上書きするのも、作った中身を入れるだけ。
extension StageController {
    // MARK: - グループの中身を作る

    /// そのディスプレイのいまのステージから、グループの中身を作る（ステージが空なら nil）
    private func stageContent(on screen: NSScreen) -> StageGroup.Content? {
        let stage = self.stage(on: screen)
        let members = stageItems(on: screen).compactMap(\.signature)
        guard !members.isEmpty else { return nil }
        return StageGroup.Content(members: members, layout: stage.layout, displayID: screen.displayUUID, desktopID: currentDesktopID(on: screen))
    }

    /// そのディスプレイで、いま表に出ているデスクトップの UUID（保存したグループは、このデスクトップのウインドウバーに出す。分からなければ nil で、すべてのデスクトップ）
    private func currentDesktopID(on screen: NSScreen) -> String? {
        guard SkyLight.isAvailable, let displays = SkyLight.displays(),
              let display = SkyLight.display(forKey: Self.displayKey(screen), in: displays)
        else { return nil }
        return display.spaces.first { $0.id == display.current }?.uuid
    }

    /// デスクトップの番号から、その UUID（グループを出すデスクトップとして覚える値。分からなければ nil）
    private func desktopID(of space: UInt64?) -> String? {
        space.flatMap { desktopUUIDs[$0] }
    }

    /// 見えている画面から、グループの中身を作る（位置・大きさ・重なりの順番ごと記録する）。ステージも、その組み合わせにする
    private func recordedContent(on screen: NSScreen) -> StageGroup.Content? {
        let arrangement = visibleArrangement(on: screen).filter { $0.item.signature != nil }
        guard !arrangement.isEmpty else { return nil }
        let layout = LayoutChoice.recording(arrangement.map(\.frame), in: stageArea(on: screen))
        updateStage(on: screen, apply: false) { stage in
            stage.selection.replace(with: arrangement.map(\.item.id))
            stage.layout = layout
        }
        return StageGroup.Content(
            members: arrangement.compactMap(\.item.signature),
            layout: layout,
            displayID: screen.displayUUID,
            desktopID: currentDesktopID(on: screen)
        )
    }

    /// そのディスプレイに見えているウインドウと、その枠（後ろから前の順。いまのデスクトップの、最小化していないもの）
    private func visibleArrangement(on screen: NSScreen) -> [(item: WindowItem, frame: CGRect)] {
        let frames = AXWindow.frames(of: windows)
        let locator = DisplayLocator()
        let key = Self.displayKey(screen)
        return CurrentSpace.frontToBack(among: windows, frames: frames)
            .compactMap { item -> (item: WindowItem, frame: CGRect)? in
                guard let frame = frames[item.id], locator.key(for: frame) == key else { return nil }
                return (item, frame)
            }
            .reversed()
    }

    // MARK: - 保存する・上書きする

    /// そのディスプレイのステージをグループとして保存する（名前がなければ仮の名前）。保存したグループを返す
    @discardableResult
    func saveStageAsGroup(on screen: NSScreen, name: String? = nil) -> StageGroup? {
        guard let content = stageContent(on: screen) else { return nil }
        return editLibrary { $0.addGroup(name: name, content: content) }
    }

    /// 見えている画面を、位置・大きさ・重なりの順番ごとグループとして記録する（ステージも、その組み合わせにする）
    func recordScreenAsGroup(on screen: NSScreen) {
        guard let content = recordedContent(on: screen) else { return }
        editLibrary { $0.addGroup(name: nil, content: content) }
    }

    /// そのディスプレイのいまのステージで、グループの中身・並べ方・ディスプレイを上書きする（名前と並び順はそのまま）
    func overwriteGroup(_ id: UUID, on screen: NSScreen) {
        guard let content = stageContent(on: screen) else { return }
        editLibrary { $0.setContent(content, ofGroup: id) }
    }

    /// 見えている画面で、グループを記録し直す（名前と並び順はそのまま）
    func rerecordGroup(_ id: UUID, on screen: NSScreen) {
        guard library.group(id: id) != nil, let content = recordedContent(on: screen) else { return }
        editLibrary { $0.setContent(content, ofGroup: id) }
    }

    // MARK: - 編集する

    /// グループの編集画面で直したグループを保存する（同じ ID のグループを置き換える）
    func updateGroup(_ group: StageGroup) {
        editLibrary { $0.updateGroup(group) }
    }

    /// グループの並べ方を変える（右クリックの「並べ方」）。選んだらすぐ、ステージに映す
    /// - そのグループを呼び出したまま、ステージの中身を変えていなければ、その場で並び直す
    /// - そうでなければ、そのグループを、選んだ並べ方で呼び出す
    /// - Parameter fallback: グループにディスプレイを決めていないときに出すディスプレイ（右クリックしたウインドウバーのディスプレイ）
    func setLayout(_ choice: LayoutChoice, ofGroup id: UUID, fallback: NSScreen?) {
        guard var group = library.group(id: id) else { return }
        if group.layout != choice {
            group.layout = choice
            updateGroup(group)
        }
        if lastRecalledGroupID == id, let shown = lastRecalledStage,
           let screen = NSScreen.screens.first(where: { Self.displayKey($0) == shown.screenKey }),
           Set(stage(on: screen).selection.members) == shown.windows {
            setLayout(choice, on: screen)
        } else {
            let updated = group
            Task { await recall(updated, fallback: fallback) }
        }
    }

    func renameGroup(_ id: UUID, to name: String) {
        editLibrary { $0.renameGroup(id, to: name) }
    }

    func deleteGroup(_ id: UUID) {
        editLibrary { $0.removeGroup(id) }
    }

    // MARK: - 中身をドラッグで直す（ストリップから）

    /// ウインドウをグループに足す（ウインドウの行をグループの行の上で離した）
    func addWindow(_ item: WindowItem, toGroup id: UUID) {
        guard let signature = item.signature else { return }
        editLibrary { $0.addMember(signature, toGroup: id) }
    }

    /// グループから中身を外す（見本のアイコンを、グループの行の外で離した）。最後の 1 つなら、グループごと削除するか聞く
    func removeMember(at index: Int, fromGroup id: UUID) {
        guard let group = library.group(id: id), group.members.indices.contains(index) else { return }
        if group.members.count == 1 {
            guard Confirmation.ask(
                title: "「\(group.name)」の最後のウインドウです",
                message: "外すとグループが空になります。グループごと削除しますか？",
                action: "グループを削除"
            ) else { return }
            deleteGroup(id)
            return
        }
        editLibrary { $0.removeMember(at: index, fromGroup: id) }
    }

    /// 中身をほかのグループへ移す（見本のアイコンを、ほかのグループの行の上で離した）。元のグループが空になったら、削除するか聞く
    func moveMember(at index: Int, from source: UUID, to destination: UUID) {
        guard editLibrary({ $0.moveMember(at: index, from: source, to: destination) }) else { return }
        if let group = library.group(id: source), group.members.isEmpty,
           Confirmation.ask(
               title: "「\(group.name)」が空になりました",
               message: "中身のないグループを削除しますか？",
               action: "削除"
           ) {
            deleteGroup(source)
        }
    }

    /// グループの中身の並び順を変える（見本のアイコンを、同じグループのほかのアイコンの上で離した）
    func reorderMember(inGroup id: UUID, from: Int, to: Int, swap: Bool) {
        editLibrary { $0.reorderMember(inGroup: id, from: from, to: to, swap: swap) }
    }

    /// グループを出すデスクトップを変える（右クリックの「出すデスクトップ」）
    /// - Parameter space: 出すデスクトップの番号（nil なら、すべてのデスクトップ）
    func setDesktop(_ space: UInt64?, ofGroup id: UUID) {
        let desktopID = desktopID(of: space)
        // 番号を渡したのに UUID が分からないときは、変えない（すべてのデスクトップになってしまわないように）
        guard space == nil || desktopID != nil else { return }
        editLibrary { $0.setDesktop(desktopID, ofGroup: id) }
    }

    /// そのデスクトップに、グループを出すデスクトップとして決められるか（UUID が分かるか）
    func canAssignGroups(toDesktop space: UInt64?) -> Bool {
        desktopID(of: space) != nil
    }

    /// グループを、そのデスクトップだけに出しているか
    func isGroup(_ group: StageGroup, onlyOnDesktop space: UInt64?) -> Bool {
        guard let desktopID = group.desktopID else { return false }
        return self.desktopID(of: space) == desktopID
    }

    // MARK: - ストリップに並べる

    /// そのディスプレイ・デスクトップのウインドウバーに並べるグループ（ウインドウバーが 1 つのときは、ディスプレイでは分けない）
    /// - Parameter space: ウインドウバーのあるデスクトップの番号（分からなければ nil で、デスクトップでは分けない）
    func groups(on screen: NSScreen, desktop space: UInt64?) -> [StageGroup] {
        let byDisplay: [StageGroup]
        if separatesDisplays {
            let connected = Set(NSScreen.screens.compactMap(\.displayUUID))
            byDisplay = library.groups(forDisplay: screen.displayUUID, connected: connected, isPrimary: screen == NSScreen.primary)
        } else {
            byDisplay = library.groups
        }
        // デスクトップごとに分ける（決まりは PinstageCore の StageGroup.isShown）
        let desktop = desktopID(of: space)
        let known = Set(desktopUUIDs.values)
        return byDisplay.filter { $0.isShown(onDesktop: desktop, knownDesktops: known) }
    }

    /// グループをドラッグで並べ替える（ショートカットの番号も変わる）
    /// index・dropIndex は、そのウインドウバーに並べているグループの番号。
    /// ほかのディスプレイ・デスクトップのグループの並びは崩さない（並び順はショートカットの番号でもある）
    func moveGroup(from index: Int, dropIndex: Int, on screen: NSScreen, desktop space: UInt64?) {
        let visible = groups(on: screen, desktop: space).map(\.id)
        editLibrary { $0.moveGroup(visible: visible, from: index, dropIndex: dropIndex) }
    }

    /// グループを出すディスプレイの名前（ディスプレイが 1 つだけなら出さない）
    func displayName(for group: StageGroup) -> String? {
        guard let id = group.displayID, NSScreen.screens.count > 1 else { return nil }
        return NSScreen.displayName(forDisplayUUID: id)
    }
}
