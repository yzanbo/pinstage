import Foundation
import os

extension Logger {
    /// Pinstage の記録（Console や make update-test-log では、subsystem「app.pinstage.Pinstage」で探す）
    ///
    /// subsystem は、試験用アプリ（ID が違う）でも同じにしておく（記録を同じ条件で探せるように）。
    init(pinstage category: String) {
        self.init(subsystem: "app.pinstage.Pinstage", category: category)
    }
}

extension Bundle {
    /// 版（CFBundleShortVersionString。例: 0.3.0）
    var shortVersion: String? {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// ビルド番号（CFBundleVersion。Sparkle は、これで新旧を比べる）
    var buildNumber: String? {
        object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}
