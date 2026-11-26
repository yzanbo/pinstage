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
///
/// メニューバーのアイコンの印は「まだ入れていない新しい版がある」の意味で、入れるか、利用者がその版を飛ばすまで出しておく
/// （更新の画面を開いた・「あとで通知」を選んだ・Pinstage を終了しただけでは消さない。Pinshelf と同じ）。
/// 終了しても消えないよう、見つけた版を UserDefaults に保存し、起動したときに、今の版より新しければ戻す。
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
    /// 見つけて、まだ入れていない新しい版（表示用の版。メニューバーで知らせる）。なければ nil
    public private(set) var pendingVersion: String?

    /// UserDefaults に保存するときのキー
    public enum Key {
        /// 見つけた新しい版（表示用の版。例: 0.3.1）
        public static let pendingVersion = "pendingUpdateVersion"
        /// 見つけた新しい版のビルド番号（CFBundleVersion。起動したときに、今の版と比べる）
        public static let pendingBuild = "pendingUpdateBuild"
    }

    /// 知らせる新しい版が変わった（メニューバーのアイコンの印を付け外しする）
    @ObservationIgnored public var onPendingVersionChange: ((String?) -> Void)?

    @ObservationIgnored private weak var service: (any AppUpdateService)?
    @ObservationIgnored private let defaults: UserDefaults

    /// - Parameters:
    ///   - defaults: 見つけた新しい版を保存する場所
    ///   - currentBuild: 今の版のビルド番号（CFBundleVersion）。保存してある版がこれより新しければ、印を戻す
    public init(defaults: UserDefaults, currentBuild: String?) {
        self.defaults = defaults
        restorePendingUpdate(currentBuild: currentBuild)
    }

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

    /// 新しい版を見つけた（入れるか飛ばすまで、メニューバーで知らせる）
    /// - Parameters:
    ///   - version: 表示用の版（例: 0.3.1）
    ///   - build: ビルド番号（CFBundleVersion）
    public func noteUpdateFound(version: String, build: String) {
        defaults.set(version, forKey: Key.pendingVersion)
        defaults.set(build, forKey: Key.pendingBuild)
        setPendingVersion(version)
    }

    /// 知らせていた版が片付いた（利用者が飛ばした・確かめ直したら新しい版がなかった）
    public func clearPendingUpdate() {
        defaults.removeObject(forKey: Key.pendingVersion)
        defaults.removeObject(forKey: Key.pendingBuild)
        setPendingVersion(nil)
    }

    /// 保存してある版が今の版より新しければ、印を戻す。入れ終えた（今の版が同じか新しい）なら、保存を消す
    private func restorePendingUpdate(currentBuild: String?) {
        guard let version = defaults.string(forKey: Key.pendingVersion),
              let build = defaults.string(forKey: Key.pendingBuild) else {
            clearPendingUpdate()
            return
        }
        if let currentBuild, !Self.isBuild(build, newerThan: currentBuild) {
            clearPendingUpdate()
            return
        }
        setPendingVersion(version)
    }

    /// ビルド番号を比べる（Sparkle と同じく、ビルド番号で新旧を決める。数字は数として比べる: 10 は 9 より新しい）
    static func isBuild(_ build: String, newerThan other: String) -> Bool {
        build.compare(other, options: .numeric) == .orderedDescending
    }

    private func setPendingVersion(_ version: String?) {
        guard version != pendingVersion else { return }
        pendingVersion = version
        onPendingVersionChange?(version)
    }
}
