import Foundation
import Observation
import ServiceManagement

/// ログイン項目としての状態
public enum LoginItemStatus: Equatable, Sendable {
    /// ログイン時に起動する
    case enabled
    /// 登録していない
    case disabled
    /// 登録したが、システム設定での許可を待っている
    case requiresApproval
    /// アプリが見つからないなどで使えない
    case unavailable
}

/// ログイン項目の登録を受け持つもの（テストでは差し替える）
public protocol LoginItemService: Sendable {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    /// システム設定の「ログイン項目」を開く
    func openSystemSettings()
}

/// macOS の SMAppService（このアプリ自身をログイン項目にする）を使う実装
public struct MainAppLoginItemService: LoginItemService {
    public init() {}

    public var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .disabled
        }
    }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// 「ログイン時に起動」の設定
///
/// システム設定の「ログイン項目」でも入れたり外したりできるので、状態は保存せず、
/// 表示するたびに macOS に問い合わせる（`refresh()`）。
@MainActor
@Observable
public final class LaunchAtLogin {
    public private(set) var status: LoginItemStatus
    /// 直前の操作が失敗したときの説明
    public private(set) var errorMessage: String?

    private let service: any LoginItemService

    public init(service: any LoginItemService = MainAppLoginItemService()) {
        self.service = service
        status = service.status
    }

    /// 登録しているか（許可待ちも含む。スイッチの表示に使う）
    public var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    /// システム設定での許可が要るか
    public var needsApproval: Bool {
        status == .requiresApproval
    }

    /// 入れる・外す
    public func setEnabled(_ enabled: Bool) {
        refresh()
        guard enabled != isRegistered else { return }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    /// macOS に今の状態を問い合わせる
    public func refresh() {
        status = service.status
    }

    /// システム設定の「ログイン項目」を開く
    public func openSystemSettings() {
        service.openSystemSettings()
    }
}
