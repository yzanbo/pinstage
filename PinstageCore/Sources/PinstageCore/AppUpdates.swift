import Foundation
import Observation

/// 更新を受け持つもの（アプリでは Sparkle を使う。テストでは差し替える）
@MainActor
public protocol AppUpdateService: AnyObject {
    /// 新しい版を自動で確かめるか
    var checksAutomatically: Bool { get set }
    /// いま確かめられるか（裏で確かめている途中・ダウンロードの途中は false）
    var canCheck: Bool { get }
    /// 最後に確かめた日時（まだ確かめていなければ nil）
    var lastCheckDate: Date? { get }
    /// 新しい版がないかを確かめ、結果を画面に出す
    func checkForUpdates()
}

/// アプリの更新の状態（設定の「一般」と、メニューバーのメニューに出す）
///
/// 更新そのもの（確かめる・落とす・入れ替える）は `AppUpdateService` が受け持つ。
/// 更新ファイルの署名を確かめる公開鍵の入っていないビルドでは、
/// 受け持つものをつながず、更新の機能は出さない。
@MainActor
@Observable
public final class AppUpdates {
    /// 更新の機能を使えるか（受け持つものがつながっているか）
    public private(set) var isAvailable = false
    /// 新しい版を自動で確かめるか
    public private(set) var checksAutomatically = false
    /// いま確かめられるか
    public private(set) var canCheck = false
    /// 最後に確かめた日時
    public private(set) var lastCheckDate: Date?
    /// 自動で見つけて、まだ見てもらっていない新しい版（メニューバーで知らせる）。なければ nil
    public private(set) var pendingVersion: String?

    /// 知らせる新しい版が変わった（メニューバーのアイコンの印を付け外しする）
    @ObservationIgnored public var onPendingVersionChange: ((String?) -> Void)?

    @ObservationIgnored private weak var service: (any AppUpdateService)?

    public init() {}

    /// 更新を受け持つものをつなぐ（アプリを起動したとき）
    public func attach(_ service: any AppUpdateService) {
        self.service = service
        isAvailable = true
        refresh()
    }

    /// 受け持つものに、今の状態を聞き直す
    public func refresh() {
        guard let service else { return }
        checksAutomatically = service.checksAutomatically
        canCheck = service.canCheck
        lastCheckDate = service.lastCheckDate
    }

    /// 自動で確かめるかを切り替える
    public func setChecksAutomatically(_ enabled: Bool) {
        service?.checksAutomatically = enabled
        refresh()
    }

    /// 新しい版がないかを確かめる（知らせていた版があれば、その更新の画面を前に出す）
    public func check() {
        service?.checkForUpdates()
    }

    /// 自動で新しい版を見つけた（画面を割り込ませず、メニューバーで知らせる）
    public func noteUpdateFound(version: String) {
        setPendingVersion(version)
    }

    /// 知らせていた版を見てもらった・片付いた
    public func clearPendingUpdate() {
        setPendingVersion(nil)
    }

    private func setPendingVersion(_ version: String?) {
        guard version != pendingVersion else { return }
        pendingVersion = version
        onPendingVersionChange?(version)
    }
}
