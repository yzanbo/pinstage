import Foundation
import Testing
@testable import PinstageCore

@Suite("アプリアイコンのバッジ")
struct AppIconBadgeTests {
    private let bundleID = "dev.example.app"
    private let launchedAt = Date(timeIntervalSince1970: 100)
    private let now = Date(timeIntervalSince1970: 110)

    private func fixture(
        _ entries: String, version: Int = 1, bundleID: String = "dev.example.app", pid: Int = 42, updatedAt: Int = 105
    ) -> Data {
        Data("""
        {"version":\(version),"bundleID":"\(bundleID)","pid":\(pid),"updatedAt":\(updatedAt),"badges":[\(entries)]}
        """.utf8)
    }

    private func decode(_ data: Data) -> [AppIconBadge]? {
        AppBadgeSnapshot.decode(data, bundleID: bundleID, pid: 42, launchedAt: launchedAt, now: now)
    }

    @Test("公開元が指定した位置・色・説明を使い、100以上の数は見た目だけ99+にする")
    func publishedBadges() throws {
        let badges = try #require(decode(fixture("""
        {"corner":"topLeft","count":2,"label":"作業中","color":"#65ACEE"},
        {"corner":"bottomLeft","count":1,"label":"回答待ち"},
        {"corner":"topRight","count":103,"label":"未読","color":"#45c66d"}
        """)))
        #expect(badges.map(\.corner) == [.topLeft, .bottomLeft, .topRight])
        #expect(badges.map(\.text) == ["2", "1", "99+"])
        #expect(badges.map(\.rgb) == [0x65ACEE, nil, 0x45C66D])
        #expect(badges.last?.description == "未読 103 件")
    }

    @Test("別のアプリ・起動前のファイル・別PID・対応しない版は読まない")
    func verifiesPublisher() {
        #expect(decode(fixture("", bundleID: "dev.other.app")) == nil)
        #expect(decode(fixture("", updatedAt: 99)) == nil)
        #expect(decode(fixture("", updatedAt: 116)) == nil)
        #expect(decode(fixture("", pid: 43)) == nil)
        #expect(decode(fixture("", version: 2)) == nil)
    }

    @Test("右下はPinstage用。重複・負の数・不正な色や大きすぎるファイルを断る")
    func rejectsInvalidPayloads() {
        #expect(decode(fixture(#"{"corner":"bottomRight","count":1,"label":"未読"}"#)) == nil)
        #expect(decode(fixture(#"{"corner":"topRight","count":-1,"label":"未読"}"#)) == nil)
        #expect(decode(fixture(##"{"corner":"topRight","count":1,"label":"未読","color":"#+00000"}"##)) == nil)
        let entry = #"{"corner":"topRight","count":1,"label":"未読"}"#
        #expect(decode(fixture("\(entry),\(entry)")) == nil)
        #expect(decode(Data(repeating: 0x20, count: AppBadgeSnapshot.maximumBytes + 1)) == nil)
    }

    @Test("置き場のファイル名からバンドルIDを取り出し、隠しファイル・書きかけ・パスになる名前は読まない")
    func bundleIDFromFileName() {
        #expect(AppBadgeSnapshot.bundleID(fromFileName: "dev.example.app.json") == "dev.example.app")
        #expect(AppBadgeSnapshot.bundleID(fromFileName: "com.example.My-App_2.json") == "com.example.My-App_2")
        #expect(AppBadgeSnapshot.bundleID(fromFileName: ".json") == nil)
        #expect(AppBadgeSnapshot.bundleID(fromFileName: ".dev.example.app.json") == nil)
        #expect(AppBadgeSnapshot.bundleID(fromFileName: "..json") == nil)
        #expect(AppBadgeSnapshot.bundleID(fromFileName: "dev.example.app.json.tmp") == nil)
        #expect(AppBadgeSnapshot.bundleID(fromFileName: "dev.example.app") == nil)
        #expect(AppBadgeSnapshot.bundleID(fromFileName: "a/b.json") == nil)
        #expect(AppBadgeSnapshot.bundleID(fromFileName: "アプリ.json") == nil)
        #expect(AppBadgeSnapshot.bundleID(fromFileName: String(repeating: "a", count: 256) + ".json") == nil)
    }

    @Test("連携があれば0件を含めて優先。未連携アプリは引き続き標準Dockバッジ")
    func mergesWithoutDuplicates() throws {
        let empty = try #require(decode(fixture(#"{"corner":"topRight","count":0,"label":"未読"}"#)))
        #expect(empty.isEmpty)
        let standard = [bundleID: "5", "dev.other.app": "•"]
        let merged = AppIconBadge.merge(standard: standard, published: [bundleID: empty])
        #expect(merged[bundleID] == [])
        #expect(merged["dev.other.app"] == [.dock("•")])
        #expect(AppIconBadge.merge(standard: standard, published: [:])[bundleID] == [.dock("5")])
    }
}
