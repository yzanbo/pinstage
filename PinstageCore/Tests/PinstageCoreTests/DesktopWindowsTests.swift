import Foundation
import Testing
@testable import PinstageCore

@Suite("デスクトップごとのウインドウの一覧")
struct DesktopWindowsTests {
    /// デスクトップ A（a1・a2）と B（b1）を、それぞれ覚えた状態
    private func visitedBoth() -> [DesktopWindows<String>] {
        var desktops = [DesktopWindows<String>(), DesktopWindows<String>()]
        DesktopAttribution.update(&desktops, isOnScreen: [true, false], windows: ["a1", "a2"], at: 0)
        DesktopAttribution.update(&desktops, isOnScreen: [false, true], windows: ["b1"], at: 100)
        return desktops
    }

    @Test("ストリップが 1 つだけ出ているときは、その一覧を、そのストリップに覚えさせる")
    func remembered() {
        var desktops = [DesktopWindows<String>(), DesktopWindows<String>()]
        let outcome = DesktopAttribution.update(&desktops, isOnScreen: [true, false], windows: ["a1", "a2"], at: 0)
        #expect(outcome == .remembered(0))
        #expect(desktops[0].windows == ["a1", "a2"])
        #expect(desktops[0].isConfirmed)
        #expect(desktops[1].windows.isEmpty)
        #expect(!desktops[1].isConfirmed)
    }

    @Test("切り替えの途中（両方のストリップが出ている）は、覚えた一覧を変えない")
    func switching() {
        var desktops = visitedBoth()
        // 切り替えの途中は、両方のデスクトップのウインドウが画面に出ている
        let outcome = DesktopAttribution.update(&desktops, isOnScreen: [true, true], windows: ["a1", "a2", "b1"], at: 200)
        #expect(outcome == .switching)
        #expect(desktops[0].windows == ["a1", "a2"])
        #expect(desktops[1].windows == ["b1"])
    }

    @Test("着いたあとは、そのデスクトップの一覧だけを入れ替え、ほかのデスクトップの一覧は持ったままにする")
    func arrival() {
        var desktops = visitedBoth()
        DesktopAttribution.update(&desktops, isOnScreen: [true, true], windows: ["a1", "a2", "b1"], at: 200)
        let outcome = DesktopAttribution.update(&desktops, isOnScreen: [true, false], windows: ["a1", "a3"], at: 201)
        #expect(outcome == .remembered(0))
        #expect(desktops[0].windows == ["a1", "a3"])
        #expect(desktops[1].windows == ["b1"])
    }

    @Test("初めて行くデスクトップへの切り替えの途中に紛れ込んだウインドウは、着いたあとで外す")
    func straysOnFirstVisit() {
        var desktops = [DesktopWindows<String>()]
        DesktopAttribution.update(&desktops, isOnScreen: [true], windows: ["a1", "a2"], at: 0)
        // 行き先にはまだストリップがないので、切り替えの途中の一覧（b1 が混ざっている）を、A のものとして覚えてしまう
        DesktopAttribution.update(&desktops, isOnScreen: [true], windows: ["a1", "a2", "b1"], at: 100)
        #expect(desktops[0].windows == ["a1", "a2", "b1"])
        // 着いたあと、行き先にストリップを作った。b1 は行き先のものなので、A から外す
        desktops.append(DesktopWindows<String>())
        let outcome = DesktopAttribution.update(&desktops, isOnScreen: [false, true], windows: ["b1"], at: 101)
        #expect(outcome == .remembered(1))
        #expect(desktops[0].windows == ["a1", "a2"])
        #expect(desktops[1].windows == ["b1"])
    }

    @Test("前から入っているウインドウは、ほかのデスクトップに出ていても外さない（すべてのデスクトップに出すウインドウ）")
    func keepsWindowsOnAllDesktops() {
        var desktops = [DesktopWindows<String>(), DesktopWindows<String>()]
        DesktopAttribution.update(&desktops, isOnScreen: [true, false], windows: ["a1", "everywhere"], at: 0)
        // 入れ替えても、前から入っているウインドウの時刻は変わらない
        DesktopAttribution.update(&desktops, isOnScreen: [true, false], windows: ["a1", "everywhere"], at: 99)
        DesktopAttribution.update(&desktops, isOnScreen: [false, true], windows: ["b1", "everywhere"], at: 100)
        #expect(desktops[0].windows == ["a1", "everywhere"])
        #expect(desktops[1].windows == ["b1", "everywhere"])
    }

    @Test("時間がたったあとは、同じウインドウがほかのデスクトップに出ていても外さない")
    func straysExpire() {
        var desktops = [DesktopWindows<String>(), DesktopWindows<String>()]
        DesktopAttribution.update(&desktops, isOnScreen: [true, false], windows: ["a1", "moved"], at: 0)
        let later = DesktopAttribution.strayInterval + 1
        DesktopAttribution.update(&desktops, isOnScreen: [false, true], windows: ["moved"], at: later)
        #expect(desktops[0].windows == ["a1", "moved"])
        // 間を置かずに切り替えたときは、紛れ込んだものとして外す
        var quick = [DesktopWindows<String>(), DesktopWindows<String>()]
        DesktopAttribution.update(&quick, isOnScreen: [true, false], windows: ["a1", "moved"], at: 0)
        DesktopAttribution.update(&quick, isOnScreen: [false, true], windows: ["moved"], at: 1)
        #expect(quick[0].windows == ["a1"])
    }

    @Test("ストリップのないデスクトップ（フルスクリーンなど）では、紛れ込んだものだけを外す")
    func noStrip() {
        var desktops = [DesktopWindows<String>()]
        DesktopAttribution.update(&desktops, isOnScreen: [true], windows: ["a1"], at: 0)
        DesktopAttribution.update(&desktops, isOnScreen: [true], windows: ["a1", "full"], at: 100)
        let outcome = DesktopAttribution.update(&desktops, isOnScreen: [false], windows: ["full"], at: 101)
        #expect(outcome == .noStrip)
        #expect(desktops[0].windows == ["a1"])
    }

    @Test("まだ一覧を覚えていないストリップには、切り替えの途中でも、ほかのストリップの分を引いたものを仮に入れる")
    func provisional() {
        var desktops = [DesktopWindows<String>(), DesktopWindows<String>()]
        DesktopAttribution.update(&desktops, isOnScreen: [true, false], windows: ["a1", "a2"], at: 0)
        let outcome = DesktopAttribution.update(&desktops, isOnScreen: [true, true], windows: ["a1", "a2", "b1"], at: 100)
        #expect(outcome == .switching)
        #expect(desktops[0].windows == ["a1", "a2"])
        #expect(desktops[1].windows == ["b1"])
        #expect(!desktops[1].isConfirmed)
        // 着いたあとの一覧で、覚え直す
        DesktopAttribution.update(&desktops, isOnScreen: [false, true], windows: ["b1", "b2"], at: 101)
        #expect(desktops[1].windows == ["b1", "b2"])
        #expect(desktops[1].isConfirmed)
    }

    @Test("画面に出ているストリップが、表に出ているデスクトップのものでない間は、覚えさせない")
    func departingStrip() {
        // 初めて行くデスクトップへ切り替えた直後: 前のデスクトップ（A）のストリップだけが、まだ画面に出ている
        var desktops = [DesktopWindows<String>()]
        var since: TimeInterval?
        DesktopAttribution.update(&desktops, isOnScreen: [true], isOnActiveSpace: [true], disagreeingSince: &since, windows: ["a1"], at: 0)
        #expect(since == nil)
        let outcome = DesktopAttribution.update(&desktops, isOnScreen: [true], isOnActiveSpace: [false], disagreeingSince: &since, windows: ["a1", "b1"], at: 100)
        #expect(outcome == .switching)
        #expect(since == 100)
        #expect(desktops[0].windows == ["a1"])
        // 落ち着いたら（2 つの見え方がそろったら）、また覚える
        let settled = DesktopAttribution.update(&desktops, isOnScreen: [true], isOnActiveSpace: [true], disagreeingSince: &since, windows: ["a1", "a2"], at: 101)
        #expect(settled == .remembered(0))
        #expect(since == nil)
        #expect(desktops[0].windows == ["a1", "a2"])
    }

    @Test("ずっと食い違ったままなら、画面に出ているほうを信じる")
    func disagreementTolerance() {
        var desktops = [DesktopWindows<String>()]
        var since: TimeInterval?
        DesktopAttribution.update(&desktops, isOnScreen: [true], isOnActiveSpace: [false], disagreeingSince: &since, windows: ["a1"], at: 0)
        #expect(desktops[0].windows.isEmpty)
        let later = DesktopAttribution.disagreementTolerance
        let outcome = DesktopAttribution.update(&desktops, isOnScreen: [true], isOnActiveSpace: [false], disagreeingSince: &since, windows: ["a1"], at: later)
        #expect(outcome == .remembered(0))
        #expect(desktops[0].windows == ["a1"])
    }

    @Test("2 つのストリップが画面に出ている間は、表に出ているデスクトップがどちらでも、切り替えの途中")
    func switchingIgnoresActiveSpace() {
        var desktops = visitedBoth()
        var since: TimeInterval?
        let outcome = DesktopAttribution.update(&desktops, isOnScreen: [true, true], isOnActiveSpace: [false, true], disagreeingSince: &since, windows: ["a1", "a2", "b1"], at: 200)
        #expect(outcome == .switching)
        #expect(since == nil)
        #expect(desktops[1].windows == ["b1"])
    }
}

@Suite("画面に出ているウインドウの一覧")
struct DesktopSnapshotTests {
    private let snapshot = DesktopSnapshot(
        onScreen: ["a", "full1", "full2", "lost"],
        fullScreen: ["full1": .known("D1"), "full2": .known("D2"), "lost": .unknown],
        ownWindowNumbers: [10]
    )

    @Test("フルスクリーンのウインドウは、デスクトップの一覧に入れない")
    func excludesFullScreen() {
        // デスクトップがすべてのディスプレイにまたがる設定: どのディスプレイのフルスクリーンも入れない
        #expect(snapshot.windows(onDisplay: "D1", separateSpaces: false) == ["a"])
        // ディスプレイごとに切り替える設定: ほかのディスプレイのフルスクリーンのウインドウは、そこに出たままなので入れる
        #expect(snapshot.windows(onDisplay: "D1", separateSpaces: true) == ["a", "full2"])
        #expect(snapshot.windows(onDisplay: "D2", separateSpaces: true) == ["a", "full1"])
    }

    @Test("フルスクリーンのウインドウがなければ、画面に出ているものすべて")
    func noFullScreen() {
        let plain = DesktopSnapshot<String>(onScreen: ["a", "b"], fullScreen: [:], ownWindowNumbers: [])
        #expect(plain.windows(onDisplay: "D1", separateSpaces: true) == ["a", "b"])
        #expect(!plain.showsFullScreenWindow(onDisplay: "D1", separateSpaces: false))
    }

    @Test("そのディスプレイにフルスクリーンのウインドウが出ているか")
    func showsFullScreenWindow() {
        let onD2 = DesktopSnapshot<String>(onScreen: ["full"], fullScreen: ["full": .known("D2")], ownWindowNumbers: [])
        #expect(onD2.showsFullScreenWindow(onDisplay: "D2", separateSpaces: true))
        #expect(!onD2.showsFullScreenWindow(onDisplay: "D1", separateSpaces: true))
        // デスクトップがまたがる設定なら、どのディスプレイでも同じデスクトップ
        #expect(onD2.showsFullScreenWindow(onDisplay: "D1", separateSpaces: false))
        // どのディスプレイか分からないものは、あるものとして扱う
        let unknown = DesktopSnapshot<String>(onScreen: ["full"], fullScreen: ["full": .unknown], ownWindowNumbers: [])
        #expect(unknown.showsFullScreenWindow(onDisplay: "D1", separateSpaces: true))
    }
}

@Suite("デスクトップごとのストリップの置き方")
struct DesktopPlacementTests {
    @Test("ストリップが 1 つあれば、そのまま")
    func keep() {
        var since: TimeInterval?
        let result = DesktopAttribution.placement(isOnActiveSpace: [true, false], isOnScreen: [true, false], isConfirmed: [true, true], overlappingSince: &since, at: 0)
        #expect(result.placement == .keep)
        #expect(!result.isUnsettled)
    }

    @Test("どちらで見てもストリップがなければ、初めて訪れたデスクトップ")
    func missing() {
        var since: TimeInterval?
        let result = DesktopAttribution.placement(isOnActiveSpace: [false], isOnScreen: [false], isConfirmed: [true], overlappingSince: &since, at: 0)
        #expect(result.placement == .missing)
        #expect(!result.isUnsettled)
        let none = DesktopAttribution.placement(isOnActiveSpace: [], isOnScreen: [], isConfirmed: [], overlappingSince: &since, at: 0)
        #expect(none.placement == .missing)
    }

    @Test("切り替えの動きの途中（前のストリップがまだ画面に出ている）は、作らずに待つ")
    func switching() {
        var since: TimeInterval?
        // 行き先にストリップがない: 表に出ているデスクトップにはないが、前のストリップが画面に出ている
        let first = DesktopAttribution.placement(isOnActiveSpace: [false], isOnScreen: [true], isConfirmed: [true], overlappingSince: &since, at: 0)
        #expect(first.placement == .keep)
        #expect(first.isUnsettled)
        // 行き先にもストリップがある: 両方が画面に出ている
        let both = DesktopAttribution.placement(isOnActiveSpace: [false, true], isOnScreen: [true, true], isConfirmed: [true, true], overlappingSince: &since, at: 0)
        #expect(both.placement == .keep)
        #expect(both.isUnsettled)
        #expect(since == nil)
    }

    @Test("1 つのデスクトップに重なったら、少し待ってから、一覧を覚えているほうを残す")
    func overlapping() {
        var since: TimeInterval?
        let flags = [true, true, false]
        let first = DesktopAttribution.placement(isOnActiveSpace: flags, isOnScreen: flags, isConfirmed: [false, true, true], overlappingSince: &since, at: 10)
        #expect(first.placement == .keep)
        #expect(first.isUnsettled)
        #expect(since == 10)
        let early = DesktopAttribution.placement(isOnActiveSpace: flags, isOnScreen: flags, isConfirmed: [false, true, true], overlappingSince: &since, at: 10.5)
        #expect(early.placement == .keep)
        let merged = DesktopAttribution.placement(isOnActiveSpace: flags, isOnScreen: flags, isConfirmed: [false, true, true], overlappingSince: &since, at: 10 + DesktopAttribution.overlapDelay)
        #expect(merged.placement == .merge(keep: 1, close: [0]))
        #expect(since == nil)
        // どれも覚えていなければ、古いほう（先頭）を残す
        var again: TimeInterval? = 0
        let oldest = DesktopAttribution.placement(isOnActiveSpace: flags, isOnScreen: flags, isConfirmed: [false, false, false], overlappingSince: &again, at: 5)
        #expect(oldest.placement == .merge(keep: 0, close: [1]))
    }

    @Test("重なりが解けたら、待ち時間を数え直す")
    func overlapResets() {
        var since: TimeInterval?
        _ = DesktopAttribution.placement(isOnActiveSpace: [true, true], isOnScreen: [true, true], isConfirmed: [true, true], overlappingSince: &since, at: 0)
        #expect(since == 0)
        _ = DesktopAttribution.placement(isOnActiveSpace: [false, true], isOnScreen: [true, true], isConfirmed: [true, true], overlappingSince: &since, at: 0.5)
        #expect(since == nil)
    }
}
