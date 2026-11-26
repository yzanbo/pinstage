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

/// テストごとに別の保存場所を作って渡し、終わったら消す（ふだんの設定に触れないように）
private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let suite = "AppUpdatesTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
}

@Suite("アプリの更新")
@MainActor
struct AppUpdatesTests {
    @Test("受け持つものをつなぐまでは、更新の機能を使えない（確かめても何も起きない）")
    func unavailableWithoutService() throws {
        try withDefaults { defaults in
            let updates = AppUpdates(defaults: defaults, currentBuild: "1")
            #expect(!updates.isAvailable)
            #expect(!updates.canCheck)
            updates.check()
            updates.setChecksAutomatically(true)
            #expect(!updates.checksAutomatically)
        }
    }

    @Test("つなぐと使えるようになり、受け持つものの状態を読む")
    func readsStateOnAttach() throws {
        try withDefaults { defaults in
            let service = FakeUpdateService()
            let checked = Date(timeIntervalSince1970: 1_800_000_000)
            service.lastCheckDate = checked
            let updates = AppUpdates(defaults: defaults, currentBuild: "1")

            updates.attach(service)
            #expect(updates.isAvailable)
            #expect(updates.checksAutomatically)
            #expect(updates.canCheck)
            #expect(updates.lastCheckDate == checked)
        }
    }

    @Test("自動で確かめるかの切り替えを、受け持つものに伝える")
    func togglesAutomaticChecks() throws {
        try withDefaults { defaults in
            let service = FakeUpdateService()
            let updates = AppUpdates(defaults: defaults, currentBuild: "1")
            updates.attach(service)

            updates.setChecksAutomatically(false)
            #expect(!service.checksAutomatically)
            #expect(!updates.checksAutomatically)

            updates.setChecksAutomatically(true)
            #expect(service.checksAutomatically)
            #expect(updates.checksAutomatically)
        }
    }

    @Test("確かめるように頼むと、受け持つものが確かめる")
    func forwardsCheck() throws {
        try withDefaults { defaults in
            let service = FakeUpdateService()
            let updates = AppUpdates(defaults: defaults, currentBuild: "1")
            updates.attach(service)

            updates.check()
            #expect(service.checkCount == 1)
        }
    }

    @Test("受け持つものの状態が変わったら、聞き直して反映する")
    func refreshesState() throws {
        try withDefaults { defaults in
            let service = FakeUpdateService()
            let updates = AppUpdates(defaults: defaults, currentBuild: "1")
            updates.attach(service)

            service.canCheck = false
            let checked = Date(timeIntervalSince1970: 1_800_000_500)
            service.lastCheckDate = checked
            updates.refresh()
            #expect(!updates.canCheck)
            #expect(updates.lastCheckDate == checked)
        }
    }

    @Test("見つけた新しい版を覚え、片付いたら忘れる（変わったときだけ知らせる）")
    func tracksPendingVersion() throws {
        try withDefaults { defaults in
            let updates = AppUpdates(defaults: defaults, currentBuild: "5")
            var notified: [String?] = []
            updates.onPendingVersionChange = { notified.append($0) }

            updates.noteUpdateFound(version: "0.3.1", build: "6")
            #expect(updates.pendingVersion == "0.3.1")
            // 同じ版をもう一度見つけても、知らせ直さない
            updates.noteUpdateFound(version: "0.3.1", build: "6")
            updates.clearPendingUpdate()
            #expect(updates.pendingVersion == nil)
            // もう忘れているので、知らせ直さない
            updates.clearPendingUpdate()

            #expect(notified == ["0.3.1", nil])
        }
    }

    @Test("見つけた版は、終了して起動し直しても、まだ入れていなければ印を戻す")
    func restoresPendingVersionAfterRelaunch() throws {
        try withDefaults { defaults in
            AppUpdates(defaults: defaults, currentBuild: "5").noteUpdateFound(version: "0.3.1", build: "6")

            let relaunched = AppUpdates(defaults: defaults, currentBuild: "5")
            #expect(relaunched.pendingVersion == "0.3.1")
        }
    }

    @Test("見つけた版を入れて開き直したら（今の版が同じか新しい）、印を戻さず、保存も消す")
    func forgetsPendingVersionAfterInstalling() throws {
        try withDefaults { defaults in
            AppUpdates(defaults: defaults, currentBuild: "5").noteUpdateFound(version: "0.3.1", build: "6")

            let updated = AppUpdates(defaults: defaults, currentBuild: "6")
            #expect(updated.pendingVersion == nil)
            #expect(defaults.string(forKey: AppUpdates.Key.pendingVersion) == nil)
            #expect(defaults.string(forKey: AppUpdates.Key.pendingBuild) == nil)

            // 見つけた版より新しい版を入れたときも
            AppUpdates(defaults: defaults, currentBuild: "6").noteUpdateFound(version: "0.3.2", build: "7")
            #expect(AppUpdates(defaults: defaults, currentBuild: "8").pendingVersion == nil)
        }
    }

    @Test("片付いた版（飛ばした版など）は、起動し直しても戻さない")
    func doesNotRestoreClearedVersion() throws {
        try withDefaults { defaults in
            let updates = AppUpdates(defaults: defaults, currentBuild: "5")
            updates.noteUpdateFound(version: "0.3.1", build: "6")
            updates.clearPendingUpdate()

            #expect(AppUpdates(defaults: defaults, currentBuild: "5").pendingVersion == nil)
        }
    }

    @Test("ビルド番号は数として比べる（10 は 9 より新しい）")
    func comparesBuildsNumerically() {
        #expect(AppUpdates.isBuild("10", newerThan: "9"))
        #expect(!AppUpdates.isBuild("9", newerThan: "10"))
        #expect(!AppUpdates.isBuild("6", newerThan: "6"))
    }
}
