import Foundation

/// 保存したグループ（どのウインドウを、どの型で、どのディスプレイに並べるか。どのデスクトップのウインドウバーに出すか）
///
/// グループはウインドウを抱え込まないので、同じウインドウを複数のグループに入れられる。
public struct StageGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// 出す順番に並べたウインドウ（後ろほど前面）
    public var members: [WindowSignature]
    public var layout: LayoutChoice
    /// 出すディスプレイ（ディスプレイの UUID）。つながっていなければ、ストリップのあるディスプレイに出す
    public var displayID: String?
    /// 出すデスクトップ（macOS のデスクトップの UUID。再起動しても変わらない）。nil なら、すべてのデスクトップのウインドウバーに出す。
    /// 前の版で保存したグループは nil（すべてのデスクトップ）
    public var desktopID: String?

    public init(
        id: UUID = UUID(),
        name: String,
        members: [WindowSignature],
        layout: LayoutChoice,
        displayID: String?,
        desktopID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.layout = layout
        self.displayID = displayID
        self.desktopID = desktopID
    }

    /// そのデスクトップのウインドウバーに出すか
    ///
    /// - すべてのデスクトップに出すグループ: 出す
    /// - そのデスクトップに出すグループ: 出す
    /// - 覚えたデスクトップがもうないグループ（デスクトップを消した・ディスプレイを外した）: どこにでも出す（呼び出せなくならないように）
    /// - ウインドウバーのデスクトップが分からないとき（非公開の API が使えない）: すべて出す
    /// - Parameters:
    ///   - desktop: ウインドウバーのあるデスクトップの UUID
    ///   - knownDesktops: いまあるデスクトップの UUID
    public func isShown(onDesktop desktop: String?, knownDesktops: Set<String>) -> Bool {
        guard let desktopID, let desktop else { return true }
        return desktopID == desktop || !knownDesktops.contains(desktopID)
    }
}

/// 保存する中身（グループと登録した型）
public struct StageLibrary: Codable, Equatable, Sendable {
    /// 保存の形式の版（形式を変えたときに、古いファイルを読み替えるため）
    public var version: Int
    public var groups: [StageGroup]
    public var customLayouts: [CustomLayout]

    public static let currentVersion = 1

    public init(groups: [StageGroup] = [], customLayouts: [CustomLayout] = []) {
        version = Self.currentVersion
        self.groups = groups
        self.customLayouts = customLayouts
    }
}

/// グループと型を JSON ファイルに読み書きする
public struct StageLibraryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 既定の保存場所（Application Support/Pinstage/library.json）
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appending(path: "Pinstage", directoryHint: .isDirectory).appending(path: "library.json")
    }

    /// 読み込む。まだ保存していなければ空
    public func load() throws -> StageLibrary {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return StageLibrary() }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(StageLibrary.self, from: data)
    }

    /// 保存する（途中で落ちても壊れないよう、書き終えてから置き換える）
    public func save(_ library: StageLibrary) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: fileURL, options: .atomic)
    }

    /// 読めなかったファイルを脇へ移す（次の保存で上書きして失わないように）
    @discardableResult
    public func moveAsideUnreadable() -> URL? {
        let stamp = Int(Date().timeIntervalSince1970)
        let destination = fileURL.deletingPathExtension().appendingPathExtension("broken-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

extension StageGroup {
    /// グループの中身（どのウインドウを、どの型で、どのディスプレイに並べるか）。名前と並び順のほかのすべて
    ///
    /// いまのステージから作る・見えている画面を記録して作る、のどちらも、この形にしてからグループに入れる。
    public struct Content: Equatable, Sendable {
        public var members: [WindowSignature]
        public var layout: LayoutChoice
        public var displayID: String?
        /// 出すデスクトップ（保存したときのデスクトップ。nil ならすべてのデスクトップ）
        public var desktopID: String?

        public init(members: [WindowSignature], layout: LayoutChoice, displayID: String?, desktopID: String? = nil) {
            self.members = members
            self.layout = layout
            self.displayID = displayID
            self.desktopID = desktopID
        }
    }

    public var content: Content {
        get { Content(members: members, layout: layout, displayID: displayID, desktopID: desktopID) }
        set {
            members = newValue.members
            layout = newValue.layout
            displayID = newValue.displayID
            desktopID = newValue.desktopID
        }
    }

}

extension StageLibrary {
    public func group(id: UUID) -> StageGroup? {
        groups.first { $0.id == id }
    }

    public func groupIndex(id: UUID) -> Int? {
        groups.firstIndex { $0.id == id }
    }

    public func customLayout(id: UUID) -> CustomLayout? {
        customLayouts.first { $0.id == id }
    }

    /// グループを足す（名前が空なら「グループ 1」のような仮の名前）。足したグループを返す
    @discardableResult
    public mutating func addGroup(name: String?, content: StageGroup.Content) -> StageGroup {
        let group = StageGroup(
            name: name.flatMap(GroupNaming.normalized) ?? GroupNaming.nextName(existing: groups.map(\.name)),
            members: content.members,
            layout: content.layout,
            displayID: content.displayID,
            desktopID: content.desktopID
        )
        groups.append(group)
        return group
    }

    /// グループの中身を入れ替える（名前と並び順はそのまま）。入れ替えたら true
    @discardableResult
    public mutating func setContent(_ content: StageGroup.Content, ofGroup id: UUID) -> Bool {
        guard let index = groupIndex(id: id) else { return false }
        groups[index].content = content
        return true
    }

    /// グループを出すデスクトップを変える（nil なら、すべてのデスクトップ）。変えたら true
    @discardableResult
    public mutating func setDesktop(_ desktopID: String?, ofGroup id: UUID) -> Bool {
        guard let index = groupIndex(id: id), groups[index].desktopID != desktopID else { return false }
        groups[index].desktopID = desktopID
        return true
    }

    /// 編集したグループで、同じ ID のグループを置き換える（名前が空なら、前の名前のまま）。置き換えたら true
    @discardableResult
    public mutating func updateGroup(_ group: StageGroup) -> Bool {
        guard let index = groupIndex(id: group.id) else { return false }
        var edited = group
        edited.name = GroupNaming.normalized(group.name) ?? groups[index].name
        groups[index] = edited
        return true
    }

    /// グループの名前を変える（空の名前には変えない）。変えたら true
    @discardableResult
    public mutating func renameGroup(_ id: UUID, to name: String) -> Bool {
        guard let name = GroupNaming.normalized(name), let index = groupIndex(id: id) else { return false }
        groups[index].name = name
        return true
    }

    public mutating func removeGroup(_ id: UUID) {
        groups.removeAll { $0.id == id }
    }

    /// 一部のグループだけを見せている一覧（そのディスプレイのストリップ）で並べ替える。見えていないグループの並びは崩さない
    /// - Parameters:
    ///   - visible: 見えているグループ（全体と同じ順番）
    ///   - from: 見えている中での番号
    ///   - dropIndex: 見えている中での、落とす位置（その番号の前）
    public mutating func moveGroup(visible: [UUID], from: Int, dropIndex: Int) {
        let order = ListReorder.movedSubset(all: groups.map(\.id), visible: visible, from: from, dropIndex: dropIndex)
        let byID = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        groups = order.compactMap { byID[$0] }
    }
}

extension StageLibrary {
    /// 仮の型の名前（マイ型 1・マイ型 2 …）
    public var nextCustomLayoutName: String {
        GroupNaming.nextName(prefix: GroupNaming.layoutPrefix, existing: customLayouts.map(\.name))
    }

    /// 枠の並びを、仮の名前の型として登録する。登録した型を返す
    @discardableResult
    public mutating func addCustomLayout(slots: [UnitRect]) -> CustomLayout {
        let layout = CustomLayout(name: nextCustomLayoutName, slots: slots)
        customLayouts.append(layout)
        return layout
    }

    /// 作った・直した型を入れる（同じ ID があれば置き換える）
    public mutating func saveCustomLayout(_ layout: CustomLayout) {
        if let index = customLayouts.firstIndex(where: { $0.id == layout.id }) {
            customLayouts[index] = layout
        } else {
            customLayouts.append(layout)
        }
    }

    /// 型の名前を変える（空の名前には変えない）。変えたら true
    @discardableResult
    public mutating func renameCustomLayout(_ id: UUID, to name: String) -> Bool {
        guard let name = GroupNaming.normalized(name), let index = customLayouts.firstIndex(where: { $0.id == id }) else { return false }
        customLayouts[index].name = name
        return true
    }

    /// 型を消す。その型を使っていたグループは「自動」にする
    public mutating func removeCustomLayout(_ id: UUID) {
        customLayouts.removeAll { $0.id == id }
        for index in groups.indices where groups[index].layout == .custom(id) {
            groups[index].layout = .builtIn(.auto)
        }
    }
}

extension StageLibrary {
    /// グループに中身を足す（もう入っていれば何もしない）。足したら true
    @discardableResult
    public mutating func addMember(_ member: WindowSignature, toGroup id: UUID) -> Bool {
        guard let index = groupIndex(id: id), !groups[index].members.contains(member) else { return false }
        groups[index].members.append(member)
        return true
    }

    /// グループから中身を外す。外したものを返す
    @discardableResult
    public mutating func removeMember(at memberIndex: Int, fromGroup id: UUID) -> WindowSignature? {
        guard let index = groupIndex(id: id), groups[index].members.indices.contains(memberIndex) else { return nil }
        return groups[index].members.remove(at: memberIndex)
    }

    /// 中身をほかのグループへ移す（移す先にもう入っていれば、元から外すだけ）。移したら true
    @discardableResult
    public mutating func moveMember(at memberIndex: Int, from source: UUID, to destination: UUID) -> Bool {
        guard source != destination,
              group(id: destination) != nil,
              let member = removeMember(at: memberIndex, fromGroup: source)
        else { return false }
        addMember(member, toGroup: destination)
        return true
    }
}

extension StageLibrary {
    /// グループの中身の並び順を変える（並び順は、呼び出したときに並べる順番。型の枠の番号と同じ）
    ///
    /// - swap が true: from と to を入れ替える（並びの見本・2×2 のように、場所で並んでいるとき）
    /// - swap が false: from を to の位置へ差し込む（横 1 列のように、順に並んでいるとき）
    @discardableResult
    public mutating func reorderMember(inGroup id: UUID, from: Int, to: Int, swap: Bool) -> Bool {
        guard let index = groupIndex(id: id),
              groups[index].members.indices.contains(from),
              groups[index].members.indices.contains(to),
              from != to
        else { return false }
        if swap {
            groups[index].members.swapAt(from, to)
        } else {
            // to の位置にちょうど入るよう、後ろへ移すときは 1 つ後ろに落とす
            groups[index].members = ListReorder.moved(groups[index].members, from: from, dropIndex: to > from ? to + 1 : to)
        }
        return true
    }
}

extension StageLibrary {
    /// そのディスプレイのストリップに並べるグループ（並び順は全体のまま）
    ///
    /// - ディスプレイを決めていないグループ（ポインタのあるディスプレイに出す）: どのストリップにも並べる
    /// - そのディスプレイに出すグループ: 並べる
    /// - 覚えたディスプレイがつながっていないグループ: メインのディスプレイのストリップに並べる（呼び出せなくならないように）
    /// - Parameters:
    ///   - displayID: ストリップのあるディスプレイの UUID
    ///   - connected: つながっているディスプレイの UUID
    ///   - isPrimary: ストリップのあるディスプレイが、メインのディスプレイか
    public func groups(forDisplay displayID: String?, connected: Set<String>, isPrimary: Bool) -> [StageGroup] {
        groups.filter { group in
            guard let groupDisplay = group.displayID else { return true }
            if groupDisplay == displayID { return true }
            return !connected.contains(groupDisplay) && isPrimary
        }
    }
}
