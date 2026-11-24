import Foundation
import Synchronization
import Testing
@testable import PinstageCore

/// テスト用のログイン項目（登録の結果を決めておける）
private final class FakeLoginItemService: LoginItemService {
    private struct State {
        var status: LoginItemStatus
        /// 登録したときになる状態
        var statusAfterRegister: LoginItemStatus = .enabled
        var registerError: (any Error)?
        var registerCount = 0
        var unregisterCount = 0
        var openedSettings = false
    }

    private let state: Mutex<State>

    init(status: LoginItemStatus) {
        state = Mutex(State(status: status))
    }

    var status: LoginItemStatus { state.withLock { $0.status } }
    var registerCount: Int { state.withLock { $0.registerCount } }
    var unregisterCount: Int { state.withLock { $0.unregisterCount } }
    var openedSettings: Bool { state.withLock { $0.openedSettings } }

    func willRegister(as status: LoginItemStatus) {
        state.withLock { $0.statusAfterRegister = status }
    }

    func failRegister(with error: any Error) {
        state.withLock { $0.registerError = error }
    }

    /// システム設定で、利用者が外した・入れたことにする
    func changeOutside(to status: LoginItemStatus) {
        state.withLock { $0.status = status }
    }

    func register() throws {
        try state.withLock {
            $0.registerCount += 1
            if let error = $0.registerError { throw error }
            $0.status = $0.statusAfterRegister
        }
    }

    func unregister() throws {
        state.withLock {
            $0.unregisterCount += 1
            $0.status = .disabled
        }
    }

    func openSystemSettings() {
        state.withLock { $0.openedSettings = true }
    }
}

private struct SampleError: LocalizedError {
    var errorDescription: String? { "登録できませんでした" }
}

@Suite("ログイン時に起動")
@MainActor
struct LaunchAtLoginTests {
    @Test("はじめは登録していない（勝手に登録しない）")
    func initiallyDisabled() {
        let service = FakeLoginItemService(status: .disabled)
        let launch = LaunchAtLogin(service: service)
        #expect(!launch.isRegistered)
        #expect(service.registerCount == 0)
    }

    @Test("入れると登録し、外すと登録をやめる")
    func enableAndDisable() {
        let service = FakeLoginItemService(status: .disabled)
        let launch = LaunchAtLogin(service: service)

        launch.setEnabled(true)
        #expect(launch.status == .enabled)
        #expect(launch.isRegistered)

        launch.setEnabled(false)
        #expect(launch.status == .disabled)
        #expect(service.unregisterCount == 1)
    }

    @Test("すでに同じ状態なら、登録し直さない")
    func noRedundantCalls() {
        let service = FakeLoginItemService(status: .enabled)
        let launch = LaunchAtLogin(service: service)
        launch.setEnabled(true)
        #expect(service.registerCount == 0)
    }

    @Test("許可待ちになったら、それを伝える")
    func requiresApproval() {
        let service = FakeLoginItemService(status: .disabled)
        service.willRegister(as: .requiresApproval)
        let launch = LaunchAtLogin(service: service)

        launch.setEnabled(true)

        #expect(launch.isRegistered)
        #expect(launch.needsApproval)
        launch.openSystemSettings()
        #expect(service.openedSettings)
    }

    @Test("登録に失敗したら、説明を出して状態は変えない")
    func registerFails() {
        let service = FakeLoginItemService(status: .disabled)
        service.failRegister(with: SampleError())
        let launch = LaunchAtLogin(service: service)

        launch.setEnabled(true)

        #expect(!launch.isRegistered)
        #expect(launch.errorMessage == "登録できませんでした")
    }

    @Test("システム設定で変えられたら、問い合わせ直したときに合わせる")
    func refreshReflectsOutsideChange() {
        let service = FakeLoginItemService(status: .enabled)
        let launch = LaunchAtLogin(service: service)
        service.changeOutside(to: .disabled)

        launch.refresh()

        #expect(!launch.isRegistered)
    }
}
