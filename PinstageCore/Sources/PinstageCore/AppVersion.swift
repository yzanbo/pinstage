import Foundation

/// アプリの版（Info.plist の CFBundleShortVersionString。project.yml で決める）
public enum AppVersion {
    /// β 版か（いちばん上の数が 0）
    public static func isBeta(_ version: String) -> Bool {
        guard let major = version.split(separator: ".").first.flatMap({ Int($0) }) else { return false }
        return major < 1
    }

    /// 設定画面に出す版（β 版なら「（β 版）」を付ける。書き方は Pinshot・Pinshelf と同じ「β 版」）
    public static func displayName(_ version: String) -> String {
        isBeta(version) ? "\(version)（β 版）" : version
    }
}
