#if DEBUG
import Foundation

/// デスクトップの切り替えの記録（開発用のビルドだけ）
///
/// ストリップの一覧が、切り替えの途中に食い違ったとき、何が起きたかをあとから確かめるために、
/// `~/Library/Logs/Pinstage/desktops.log` に書く。ウインドウの名前は書かない（番号と数だけ）。
/// 同じ内容が続く間は書かないので、切り替えたときだけ行が増える。
enum DesktopTrace {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Pinstage/desktops.log")
    /// 起動したときに、これより大きければ空にする
    private static let maximumSize = 512 * 1024
    private static var lastMessage = ""
    private static var handle: FileHandle?
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func log(_ message: String) {
        guard message != lastMessage else { return }
        lastMessage = message
        guard let handle = handle ?? open() else { return }
        handle.write(Data("\(formatter.string(from: Date())) \(message)\n".utf8))
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
}
#endif
