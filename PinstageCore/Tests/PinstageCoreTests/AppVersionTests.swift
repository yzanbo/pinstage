import PinstageCore
import Testing

@Suite("アプリの版")
struct AppVersionTests {
    @Test("1.0.0 より前は β 版で、設定画面に「（β 版）」を付ける")
    func beta() {
        #expect(AppVersion.isBeta("0.1.0"))
        #expect(AppVersion.displayName("0.1.0") == "0.1.0（β 版）")
    }

    @Test("1.0.0 からは正式版で、版だけを出す")
    func release() {
        #expect(!AppVersion.isBeta("1.0.0"))
        #expect(AppVersion.displayName("1.0.0") == "1.0.0")
        #expect(AppVersion.displayName("2.3.1") == "2.3.1")
    }

    @Test("版が読めないときは、そのまま出す")
    func unreadable() {
        #expect(!AppVersion.isBeta("—"))
        #expect(AppVersion.displayName("—") == "—")
    }
}
