import AppKit

/// macOS のステージマネージャ
///
/// オンだと、macOS がウインドウの位置と大きさを抑えるので、Pinstage が並べたとおりにならない。
/// オンかどうかは、macOS の設定（com.apple.WindowManager の GloballyEnabled）で分かる。
enum SystemStageManager {
    /// ステージマネージャがオンか
    static var isEnabled: Bool {
        CFPreferencesAppSynchronize("com.apple.WindowManager" as CFString)
        return CFPreferencesCopyAppValue("GloballyEnabled" as CFString, "com.apple.WindowManager" as CFString) as? Bool ?? false
    }

    /// システム設定の「デスクトップと Dock」を開く（ステージマネージャをオフにできる）
    static func openSettings() {
        NSWorkspace.shared.open(urlString: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")
    }
}
