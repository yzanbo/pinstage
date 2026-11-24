import Testing
@testable import PinstageCore

@Suite("デスクトップの名前")
struct DesktopNamingTests {
    private typealias Space = DesktopNaming.Space

    @Test("ディスプレイごとに、左から 1 つずつ数える")
    func numbersPerDisplay() {
        let names = DesktopNaming.names(displays: [
            [Space(id: 10, isFullScreen: false), Space(id: 11, isFullScreen: false)],
            [Space(id: 20, isFullScreen: false)],
        ])
        #expect(names[10] == DesktopName(number: 1))
        #expect(names[11] == DesktopName(number: 2))
        // 2 つ目のディスプレイは、また 1 から数える
        #expect(names[20] == DesktopName(number: 1))
    }

    @Test("フルスクリーンのデスクトップは数えず、「フルスクリーン」と呼ぶ")
    func fullScreenIsNotCounted() {
        let names = DesktopNaming.names(displays: [[
            Space(id: 1, isFullScreen: false),
            Space(id: 2, isFullScreen: true),
            Space(id: 3, isFullScreen: false),
        ]])
        #expect(names[2] == DesktopName(number: nil))
        // フルスクリーンの次のデスクトップは 2 番
        #expect(names[3] == DesktopName(number: 2))
    }

    @Test("名前と短い印は、番号から作る")
    func titleAndShortLabel() {
        #expect(DesktopName(number: 3).title == "デスクトップ 3")
        #expect(DesktopName(number: 3).shortLabel == "3")
        #expect(DesktopName(number: nil).title == "フルスクリーン")
        #expect(DesktopName(number: nil).shortLabel == "フルスクリーン")
    }

    @Test("ディスプレイがなければ、名前もない")
    func empty() {
        #expect(DesktopNaming.names(displays: []).isEmpty)
    }
}
