import Foundation

/// 動きの記録（開発用のビルドだけ。Release では何もしない）
///
/// 実機でしか起きない不具合（デスクトップの切り替え・サムネイル・ストリップの幅・並ばないウインドウ）を、
/// あとから確かめるために、`~/Library/Logs/Pinstage/desktops.log` に書く。ウインドウの名前は書かない（番号と数だけ）。
/// 種類ごとに、同じ内容が続く間は書かないので、何かが変わったときだけ行が増える。
enum DesktopTrace {
    /// 種類ごとに、同じ内容が続く間は書かない
    static func log(_ category: String, _ message: @autoclosure () -> String) {
        #if DEBUG
        let message = message()
        guard lastMessages[category] != message else { return }
        lastMessages[category] = message
        write("\(category): \(message)")
        #endif
    }

    /// 同じ内容は、起動してから 1 回だけ書く
    static func logOnce(_ category: String, _ message: @autoclosure () -> String) {
        #if DEBUG
        let line = "\(category): \(message())"
        guard written.insert(line).inserted else { return }
        write(line)
        #endif
    }

    #if DEBUG
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Pinstage/desktops.log")
    /// 起動したときに、これより大きければ空にする
    private static let maximumSize = 512 * 1024
    private static var lastMessages: [String: String] = [:]
    private static var written: Set<String> = []
    private static var handle: FileHandle?
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static func write(_ line: String) {
        guard let handle = handle ?? open() else { return }
        handle.write(Data("\(formatter.string(from: Date())) \(line)\n".utf8))
    }

    private static func open() -> FileHandle? {
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if !manager.fileExists(atPath: url.path) || size > maximumSize {
            manager.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        handle?.write(Data("---- 起動 \(Date()) ----\n".utf8))
        return handle
    }
    #endif
}
