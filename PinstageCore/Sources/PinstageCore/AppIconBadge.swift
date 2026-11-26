import Foundation

/// ウインドウバーとウインドウスイッチャーで共有するアプリアイコンの印。
public struct AppIconBadge: Equatable, Identifiable, Sendable {
    public enum Corner: String, CaseIterable, Decodable, Sendable {
        case topLeft, topRight, bottomLeft
        // 右下は Pinstage の「すべてのデスクトップ」の印に使う。
    }

    public let corner: Corner
    public let text: String
    public let description: String
    public let rgb: UInt32?
    public let isPublished: Bool
    public var id: Corner { corner }

    public static func dock(_ text: String) -> Self {
        let isDot = text == "•" || text.trimmingCharacters(in: .whitespaces).isEmpty
        return Self(corner: .topRight, text: isDot ? "•" : text,
                    description: isDot ? "通知あり" : "通知 \(text)", rgb: nil, isPublished: false)
    }

    public static func merge(standard: [String: String], published: [String: [Self]]) -> [String: [Self]] {
        // 公開元の空配列は「消す」の指示。未連携・無効のときだけ標準のバッジを使う。
        standard.mapValues { [dock($0)] }.merging(published) { _, custom in custom }
    }

    fileprivate static func published(corner: Corner, count: Int, label: String, rgb: UInt32?) -> Self {
        Self(corner: corner, text: count > 99 ? "99+" : String(count),
             description: "\(label) \(count) 件", rgb: rgb, isPublished: true)
    }
}

/// アプリが件数を公開する、小さな JSON の形式。アプリの状態名と表示位置は公開元が決める。
/// 形式は docs/BADGES.md に公開している（対応したいアプリはこれに合わせて書く）。
public enum AppBadgeSnapshot {
    public static let maximumBytes = 8192
    /// 一度に読むファイルの数の上限（置き場にファイルが溜まっても、読み直しが重くならないように）
    public static let maximumSources = 32

    /// 置き場のファイル名（`<バンドル ID>.json`）からバンドル ID を取り出す。
    /// 相手のアプリは名指しせず、置き場にあるファイルを全部候補にする。
    /// バンドル ID に使える文字（英数字・`.`・`-`・`_`）だけを通し、隠しファイルや書きかけのファイルは読まない。
    public static func bundleID(fromFileName name: String) -> String? {
        let suffix = ".json"
        guard name.hasSuffix(suffix) else { return nil }
        let bundleID = String(name.dropLast(suffix.count))
        guard (1...255).contains(bundleID.utf8.count), bundleID.first != ".",
              bundleID.utf8.allSatisfy(isBundleIDCharacter) else { return nil }
        return bundleID
    }

    private static func isBundleIDCharacter(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x2E, 0x5F: true
        default: false
        }
    }

    private struct Payload: Decodable {
        struct Entry: Decodable {
            let corner: AppIconBadge.Corner
            let count: Int
            let label: String
            let color: String?
        }

        let version: Int
        let bundleID: String
        let pid: Int32
        let updatedAt: TimeInterval
        let badges: [Entry]
    }

    /// 起動中のプロセスと照合する（終了した版や、再利用された PID の古いファイルを出さない）。
    /// nil は使えないファイル、空配列はバッジなし。
    public static func decode(
        _ data: Data, bundleID: String, pid: Int32, launchedAt: Date, now: Date
    ) -> [AppIconBadge]? {
        guard data.count <= maximumBytes, pid > 0,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == 1, payload.bundleID == bundleID, payload.pid == pid,
              payload.updatedAt >= launchedAt.timeIntervalSince1970,
              payload.updatedAt <= now.timeIntervalSince1970 + 5,
              payload.badges.count <= AppIconBadge.Corner.allCases.count else { return nil }

        var seen: Set<AppIconBadge.Corner> = []
        var items: [AppIconBadge] = []
        for entry in payload.badges {
            let label = entry.label.trimmingCharacters(in: .whitespaces)
            guard seen.insert(entry.corner).inserted, (0...1_000_000).contains(entry.count),
                  !label.isEmpty, label.count <= 32,
                  !label.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
            var rgb: UInt32?
            if let color = entry.color {
                guard let value = rgbValue(from: color) else { return nil }
                rgb = value
            }
            if entry.count > 0 {
                items.append(.published(corner: entry.corner, count: entry.count, label: label, rgb: rgb))
            }
        }
        return items
    }

    private static func rgbValue(from color: String) -> UInt32? {
        guard color.first == "#", color.utf8.count == 7, color.utf8.dropFirst().allSatisfy(isHexDigit) else { return nil }
        return UInt32(color.dropFirst(), radix: 16)
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x30...0x39, 0x41...0x46, 0x61...0x66: true
        default: false
        }
    }
}
