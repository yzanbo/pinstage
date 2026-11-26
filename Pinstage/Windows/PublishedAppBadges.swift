import AppKit
import Darwin
import Foundation
import PinstageCore

/// アプリが置き場に書いたバッジを、同じ利用者のローカルファイルから読む。
/// 相手のアプリは名指ししない。置き場にある `<バンドル ID>.json` を全部候補にし、
/// そのアプリが起動中で、中身がその起動と合うものだけを使う（形式は docs/BADGES.md）。
enum PublishedAppBadges {
    static func read() -> [String: [AppIconBadge]] {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return [:] }
        let directory = support.appendingPathComponent("Pinstage/BadgeSources", isDirectory: true)
        let now = Date()
        var badges: [String: [AppIconBadge]] = [:]
        for bundleID in sources(in: directory) {
            badges[bundleID] = read(bundleID: bundleID, in: directory, now: now)
        }
        return badges
    }

    /// 置き場にあるファイルから、読む候補のバンドル ID を集める（名前順に、上限まで）
    private static func sources(in directory: URL) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return Array(names.compactMap(AppBadgeSnapshot.bundleID(fromFileName:)).sorted()
            .prefix(AppBadgeSnapshot.maximumSources))
    }

    private static func read(bundleID: String, in directory: URL, now: Date) -> [AppIconBadge]? {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { !$0.isTerminated }
        guard !running.isEmpty,
              let data = readFile(directory.appendingPathComponent("\(bundleID).json")) else { return nil }
        for app in running {
            guard let launchedAt = app.launchDate else { continue }
            if let badges = AppBadgeSnapshot.decode(data, bundleID: bundleID, pid: app.processIdentifier,
                                                   launchedAt: launchedAt, now: now) {
                // 空配列も有効な結果。Dock 側に戻さない。
                return badges
            }
        }
        return nil
    }

    private static func readFile(_ url: URL) -> Data? {
        // 普通のファイルだけを上限付きで読む。リンクや名前付きパイプは追わず、読み直しが止まらないようにする。
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        }
        guard descriptor >= 0 else { return nil }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size <= AppBadgeSnapshot.maximumBytes else { return nil }
        return try? file.read(upToCount: AppBadgeSnapshot.maximumBytes + 1)
    }
}
