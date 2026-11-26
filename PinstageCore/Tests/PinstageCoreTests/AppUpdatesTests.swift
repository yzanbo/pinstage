import Foundation
import Testing
@testable import PinstageCore

/// テスト用の、更新を受け持つもの（呼ばれたことを覚える）
@MainActor
private final class FakeUpdateService: AppUpdateService {
    var checksAutomatically = true
    var canCheck = true
    var lastCheckDate: Date?
    var checkCount = 0

    func checkForUpdates() {
        checkCount += 1
    }
}

@Suite("アプリの更新")
@MainActor
struct AppUpdatesTests {
    @Test("受け持つものをつなぐまでは、更新の機能を使えない（確かめても何も起きない）")
    func unavailableWithoutService() {
        let updates = AppUpdates()
        #expect(!updates.isAvailable)
        #expect(!updates.canCheck)
        updates.check()
        updates.setChecksAutomatically(true)
        #expect(!updates.checksAutomatically)
    }

    @Test("つなぐと使えるようになり、受け持つものの状態を読む")
    func readsStateOnAttach() {
        let service = FakeUpdateService()
        let checked = Date(timeIntervalSince1970: 1_800_000_000)
        service.lastCheckDate = checked
        let updates = AppUpdates()

        updates.attach(service)
        #expect(updates.isAvailable)
        #expect(updates.checksAutomatically)
        #expect(updates.canCheck)
        #expect(updates.lastCheckDate == checked)
    }

    @Test("自動で確かめるかの切り替えを、受け持つものに伝える")
    func togglesAutomaticChecks() {
        let service = FakeUpdateService()
        let updates = AppUpdates()
        updates.attach(service)

        updates.setChecksAutomatically(false)
        #expect(!service.checksAutomatically)
        #expect(!updates.checksAutomatically)

        updates.setChecksAutomatically(true)
        #expect(service.checksAutomatically)
        #expect(updates.checksAutomatically)
    }

    @Test("確かめるように頼むと、受け持つものが確かめる")
    func forwardsCheck() {
        let service = FakeUpdateService()
        let updates = AppUpdates()
        updates.attach(service)

        updates.check()
        #expect(service.checkCount == 1)
    }

    @Test("受け持つものの状態が変わったら、聞き直して反映する")
    func refreshesState() {
        let service = FakeUpdateService()
        let updates = AppUpdates()
        updates.attach(service)

        service.canCheck = false
        let checked = Date(timeIntervalSince1970: 1_800_000_500)
        service.lastCheckDate = checked
        updates.refresh()
        #expect(!updates.canCheck)
        #expect(updates.lastCheckDate == checked)
    }

    @Test("自動で見つけた新しい版を覚え、見てもらったら忘れる（変わったときだけ知らせる）")
    func tracksPendingVersion() {
        let updates = AppUpdates()
        var notified: [String?] = []
        updates.onPendingVersionChange = { notified.append($0) }

        updates.noteUpdateFound(version: "0.3.1")
        #expect(updates.pendingVersion == "0.3.1")
        // 同じ版をもう一度見つけても、知らせ直さない
        updates.noteUpdateFound(version: "0.3.1")
        updates.clearPendingUpdate()
        #expect(updates.pendingVersion == nil)
        // もう忘れているので、知らせ直さない
        updates.clearPendingUpdate()

        #expect(notified == ["0.3.1", nil])
    }
}
