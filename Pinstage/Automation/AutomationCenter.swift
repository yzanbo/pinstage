import AppKit
import PinstageCore

/// 外から頼まれた操作（URL・「ショートカット」アプリ）を行う
///
/// どちらから頼まれても、同じ操作はここを通す。
final class AutomationCenter {
    /// 動いている Pinstage の、操作を行う役（「ショートカット」アプリの操作から使う）
    static weak var shared: AutomationCenter?

    private let stage: StageController
    private let strips: StripManager
    private let search: SearchController

    init(stage: StageController, strips: StripManager, search: SearchController) {
        self.stage = stage
        self.strips = strips
        self.search = search
    }

    /// 保存しているグループ（「ショートカット」アプリの、グループを選ぶ欄に出す）
    var groups: [StageGroup] {
        stage.library.groups
    }

    /// 操作を行う。グループが見つからない・ステージが空のときは、理由を投げる
    func perform(_ command: PinstageCommand) async throws {
        switch command {
        case .recallGroup(let key):
            guard let group = stage.library.group(matching: key) else { throw AutomationError.groupNotFound(key) }
            await stage.recall(group, fallback: StageController.screenUnderPointer)
        case .nextGroup:
            stage.recallAdjacentGroup(forward: true)
        case .previousGroup:
            stage.recallAdjacentGroup(forward: false)
        case .strip(let visibility):
            switch visibility {
            case .show: strips.setShown(true)
            case .hide: strips.setShown(false)
            case .toggle: strips.toggle()
            }
        case .search:
            search.show()
        case .saveStageAsGroup(let name):
            guard let screen = StageController.screenUnderPointer,
                  stage.saveStageAsGroup(on: screen, name: name) != nil
            else { throw AutomationError.emptyStage }
        }
    }

    /// URL で頼まれた操作を行う（読めない URL・できなかった操作は、何もしない）
    func open(_ url: URL) {
        guard let command = PinstageURL.parse(url) else { return }
        Task { try? await perform(command) }
    }

    /// 動いている Pinstage の操作を行う役。「ショートカット」アプリから Pinstage を起動したばかりのときは、用意ができるまで少し待つ
    static func waitForShared() async throws -> AutomationCenter {
        for _ in 0..<40 {
            if let shared { return shared }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw AutomationError.notReady
    }
}

/// 自動化で頼まれた操作ができなかった理由（「ショートカット」アプリに出す）
enum AutomationError: LocalizedError {
    case groupNotFound(String)
    case emptyStage
    case notReady

    var errorDescription: String? {
        switch self {
        case .groupNotFound(let key): "グループ「\(key)」が見つかりません。"
        case .emptyStage: "ステージにウインドウがありません。ウインドウバーでウインドウを選んでから保存してください。"
        case .notReady: "Pinstage の用意ができていません。少し待ってから、もう一度お試しください。"
        }
    }
}
