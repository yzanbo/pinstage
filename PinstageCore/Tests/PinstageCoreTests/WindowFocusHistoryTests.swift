import Testing
@testable import PinstageCore

@Suite("前面で使ったウインドウの順番")
struct WindowFocusHistoryTests {
    @Test("最近使った順で一度ずつ並べ、まだ使っていないものはウインドウバー順")
    func recentOrder() {
        var history = WindowFocusHistory<String>()
        history.record("b")
        history.record("d")
        history.record("b")
        #expect(history.mostRecent == "b")
        #expect(history.ordered(["a", "b", "c", "d", "b"]) == ["b", "d", "a", "c"])
    }

    @Test("記録した順番から閉じたウインドウを取り除く")
    func pruning() {
        var history = WindowFocusHistory<String>()
        history.record("b")
        history.record("a")
        history.prune(keeping: ["b"])
        #expect(history.mostRecent == "b")
        #expect(history.ordered(["c", "a", "b"]) == ["b", "c", "a"])
    }
}
