import CoreGraphics
import Foundation
import Testing
@testable import PinstageCore

@Suite("グループの書き換え")
struct StageLibraryGroupTests {
    private let safari = WindowSignature(bundleID: "com.apple.Safari", title: "資料")
    private let notes = WindowSignature(bundleID: "com.apple.Notes", title: "メモ")

    private func content(_ members: [WindowSignature], layout: LayoutChoice = .builtIn(.auto)) -> StageGroup.Content {
        StageGroup.Content(members: members, layout: layout, hasGap: false, displayID: "D1")
    }

    @Test("グループを足す。名前が空なら仮の名前、あれば前後の空白を除く")
    func addGroup() {
        var library = StageLibrary()
        let first = library.addGroup(name: nil, content: content([safari]))
        let second = library.addGroup(name: "  開発  ", content: content([notes], layout: .builtIn(.rows)))
        let third = library.addGroup(name: "   ", content: content([safari]))
        #expect(first.name == "グループ 1")
        #expect(second.name == "開発")
        #expect(third.name == "グループ 2")
        #expect(library.groups.map(\.id) == [first.id, second.id, third.id])
        #expect(library.group(id: second.id)?.content == content([notes], layout: .builtIn(.rows)))
    }

    @Test("中身を入れ替えても、名前と並び順はそのまま")
    func setContent() {
        var library = StageLibrary()
        let first = library.addGroup(name: "開発", content: content([safari]))
        let second = library.addGroup(name: "資料", content: content([notes]))
        let recorded = StageGroup.Content(members: [notes, safari], layout: .recorded([]), hasGap: false, displayID: "D2")
        let replaced = library.setContent(recorded, ofGroup: first.id)
        #expect(replaced)
        #expect(library.groups.map(\.name) == ["開発", "資料"])
        #expect(library.groups[0].content == recorded)
        #expect(library.groups[1].id == second.id)
        let unknown = library.setContent(recorded, ofGroup: UUID())
        #expect(!unknown)
    }

    @Test("編集したグループで置き換える。名前を空にしたら、前の名前のまま")
    func updateGroup() {
        var library = StageLibrary()
        var group = library.addGroup(name: "開発", content: content([safari]))
        group.name = "  "
        group.members = [notes]
        let updated = library.updateGroup(group)
        #expect(updated)
        #expect(library.groups[0].name == "開発")
        #expect(library.groups[0].members == [notes])
        group.name = "資料作り"
        library.updateGroup(group)
        #expect(library.groups[0].name == "資料作り")
        let unknown = library.updateGroup(StageGroup(name: "ない", members: [], layout: .builtIn(.auto), hasGap: false, displayID: nil))
        #expect(!unknown)
    }

    @Test("名前を変える・消す・ID で探す")
    func renameAndRemove() {
        var library = StageLibrary()
        let group = library.addGroup(name: "開発", content: content([safari]))
        let blank = library.renameGroup(group.id, to: "  ")
        let renamed = library.renameGroup(group.id, to: " 仕事 ")
        #expect(!blank)
        #expect(renamed)
        #expect(library.group(id: group.id)?.name == "仕事")
        #expect(library.groupIndex(id: group.id) == 0)
        library.removeGroup(group.id)
        #expect(library.group(id: group.id) == nil)
        #expect(library.groupIndex(id: group.id) == nil)
    }

    @Test("見えているグループの中で並べ替えても、見えていないグループの並びは崩さない")
    func moveGroup() {
        var library = StageLibrary()
        let a = library.addGroup(name: "A", content: content([safari]))
        let hidden = library.addGroup(name: "ほかのディスプレイ", content: content([safari]))
        let b = library.addGroup(name: "B", content: content([safari]))
        let c = library.addGroup(name: "C", content: content([safari]))
        // 見えているのは A・B・C。C をいちばん上へ
        library.moveGroup(visible: [a.id, b.id, c.id], from: 2, dropIndex: 0)
        #expect(library.groups.map(\.name) == ["C", "A", "ほかのディスプレイ", "B"])
        #expect(library.groups.contains { $0.id == hidden.id })
    }
}

@Suite("登録した型の書き換え")
struct StageLibraryLayoutTests {
    private let slot = UnitRect(x: 0, y: 0, width: 0.5, height: 1)

    @Test("仮の名前で登録する")
    func addCustomLayout() {
        var library = StageLibrary()
        let first = library.addCustomLayout(slots: [slot])
        let second = library.addCustomLayout(slots: [slot])
        #expect(first.name == "マイ型 1")
        #expect(second.name == "マイ型 2")
        #expect(library.nextCustomLayoutName == "マイ型 3")
        #expect(library.customLayout(id: second.id) == second)
    }

    @Test("同じ ID の型は置き換え、なければ足す")
    func saveCustomLayout() {
        var library = StageLibrary()
        var layout = library.addCustomLayout(slots: [slot])
        layout.slots = [slot, slot]
        library.saveCustomLayout(layout)
        #expect(library.customLayouts.count == 1)
        #expect(library.customLayouts[0].slots.count == 2)
        library.saveCustomLayout(CustomLayout(name: "新しい型", slots: [slot]))
        #expect(library.customLayouts.map(\.name) == ["マイ型 1", "新しい型"])
    }

    @Test("名前を変える（空の名前には変えない）")
    func renameCustomLayout() {
        var library = StageLibrary()
        let layout = library.addCustomLayout(slots: [slot])
        let blank = library.renameCustomLayout(layout.id, to: "")
        let renamed = library.renameCustomLayout(layout.id, to: "左右")
        #expect(!blank)
        #expect(renamed)
        #expect(library.customLayouts[0].name == "左右")
    }

    @Test("型を消すと、その型を使っていたグループは「自動（均等）」になる")
    func removeCustomLayout() {
        var library = StageLibrary()
        let layout = library.addCustomLayout(slots: [slot])
        let member = WindowSignature(bundleID: "com.apple.Safari", title: "")
        library.addGroup(name: "型を使う", content: StageGroup.Content(members: [member], layout: .custom(layout.id), hasGap: false, displayID: nil))
        library.addGroup(name: "使わない", content: StageGroup.Content(members: [member], layout: .builtIn(.rows), hasGap: false, displayID: nil))
        library.removeCustomLayout(layout.id)
        #expect(library.customLayouts.isEmpty)
        #expect(library.groups.map(\.layout) == [.builtIn(.auto), .builtIn(.rows)])
    }
}

@Suite("並べ方から枠と名前を決める")
struct LayoutChoiceTests {
    private let area = CGRect(x: 100, y: 50, width: 1200, height: 800)
    private let custom = CustomLayout(name: "左右", slots: [UnitRect(x: 0, y: 0, width: 0.4, height: 1), UnitRect(x: 0.4, y: 0, width: 0.6, height: 1)])

    @Test("用意した型は、型の計算のとおり（余白も）")
    func builtIn() {
        let frames = LayoutChoice.builtIn(.mainLeft).frames(count: 3, in: area, gap: 16, customLayouts: [])
        #expect(frames == StageLayout.frames(count: 3, in: area, kind: .mainLeft, gap: 16))
    }

    @Test("登録した型・記録した配置は、その枠のとおり（余白は使わない）")
    func ownSlots() {
        let expected = custom.frames(count: 2, in: area)
        #expect(LayoutChoice.custom(custom.id).frames(count: 2, in: area, gap: 16, customLayouts: [custom]) == expected)
        #expect(LayoutChoice.recorded(custom.slots).frames(count: 2, in: area, gap: 16, customLayouts: []) == expected)
        // 枠より多いウインドウは「重ねる」で置く（登録した型と同じ）
        #expect(LayoutChoice.recorded(custom.slots).frames(count: 3, in: area, gap: 0, customLayouts: []) == custom.frames(count: 3, in: area))
    }

    @Test("消した型は「自動（均等）」で並べる")
    func missingCustom() {
        let frames = LayoutChoice.custom(UUID()).frames(count: 2, in: area, gap: 16, customLayouts: [custom])
        #expect(frames == StageLayout.frames(count: 2, in: area, kind: .auto))
    }

    @Test("名前")
    func title() {
        #expect(LayoutChoice.builtIn(.rows).title(customLayouts: []) == "上下に並べる")
        #expect(LayoutChoice.custom(custom.id).title(customLayouts: [custom]) == "左右")
        #expect(LayoutChoice.custom(custom.id).title(customLayouts: []) == "自動（均等）")
        #expect(LayoutChoice.recorded([]).title(customLayouts: []) == "記録した配置")
    }

    @Test("1 枚だけのとき、大きさを変えないのは、用意した型の「重ねる」以外だけ")
    func resizesSingleWindow() {
        #expect(!LayoutChoice.builtIn(.auto).resizesSingleWindow)
        #expect(LayoutChoice.builtIn(.cascade).resizesSingleWindow)
        #expect(LayoutChoice.custom(custom.id).resizesSingleWindow)
        #expect(LayoutChoice.recorded([]).resizesSingleWindow)
    }

    @Test("見本を描くときの枠は、丸めない")
    func unitRectFrame() {
        let slot = UnitRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)
        #expect(slot.frame(in: CGSize(width: 101, height: 63)) == CGRect(x: 25.25, y: 31.5, width: 50.5, height: 15.75))
        #expect(GroupPreview.aspectRatio == 1.6)
    }

    @Test("照合の結果から、当てはまったウインドウの番号を取り出す")
    func windowIndex() {
        #expect(WindowMatcher.Match.window(3).windowIndex == 3)
        #expect(WindowMatcher.Match.missingWindow.windowIndex == nil)
        #expect(WindowMatcher.Match.appNotRunning.windowIndex == nil)
    }
}
