import AppIntents
import PinstageCore

// macOS の「ショートカット」アプリに渡す、Pinstage の操作。
// 「ショートカット」アプリの「オートメーション」（時刻・アプリの起動・ディスプレイの接続・集中モードなど）と組み合わせて、
// 自動で動かせる。Siri・Spotlight からも呼び出せる。操作は AutomationCenter（URL と同じ）を通して行う。

// MARK: - グループ

/// 「ショートカット」アプリで選べるグループ
nonisolated struct GroupEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "グループ"
    static let defaultQuery = GroupEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// 「ショートカット」アプリに、グループの一覧を渡す（動いていなければ、保存したファイルから読む）
nonisolated struct GroupEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [GroupEntity] {
        await Self.allGroups().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [GroupEntity] {
        await Self.allGroups()
    }

    @MainActor
    static func allGroups() -> [GroupEntity] {
        let groups = AutomationCenter.shared?.groups ?? []
        let source = groups.isEmpty
            ? ((try? StageLibraryStore(fileURL: StageLibraryStore.defaultFileURL()).load().groups) ?? [])
            : groups
        return source.map { GroupEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - 操作

/// グループを呼び出す
struct RecallGroupIntent: AppIntent {
    static let title: LocalizedStringResource = "グループを呼び出す"
    static let description = IntentDescription("Pinstage のグループのウインドウを、保存した並べ方で前に出します。閉じているアプリは起動し直します。")

    @Parameter(title: "グループ")
    var group: GroupEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$group) を呼び出す")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AutomationCenter.waitForShared().perform(.recallGroup(group.id.uuidString))
        return .result()
    }
}

/// ストリップを出す・隠す・切り替える
nonisolated enum StripVisibilityOption: String, AppEnum {
    case show
    case hide
    case toggle

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "ストリップ"
    static let caseDisplayRepresentations: [StripVisibilityOption: DisplayRepresentation] = [
        .show: "出す",
        .hide: "隠す",
        .toggle: "切り替える",
    ]

    var visibility: StripVisibility {
        switch self {
        case .show: .show
        case .hide: .hide
        case .toggle: .toggle
        }
    }
}

struct SetStripIntent: AppIntent {
    static let title: LocalizedStringResource = "ストリップを出す・隠す"
    static let description = IntentDescription("Pinstage のストリップ（画面の左端の一覧）を出す・隠す・切り替えます。")

    @Parameter(title: "どうするか", default: .toggle)
    var action: StripVisibilityOption

    static var parameterSummary: some ParameterSummary {
        Summary("ストリップを \(\.$action)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AutomationCenter.waitForShared().perform(.strip(action.visibility))
        return .result()
    }
}

/// ステージをグループとして保存する
struct SaveStageAsGroupIntent: AppIntent {
    static let title: LocalizedStringResource = "ステージをグループとして保存"
    static let description = IntentDescription("ポインタのあるディスプレイのステージに出しているウインドウを、グループとして保存します。")

    @Parameter(title: "名前", description: "空のときは「グループ 1」のような仮の名前にします。")
    var name: String?

    static var parameterSummary: some ParameterSummary {
        Summary("ステージを \(\.$name) という名前で保存")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AutomationCenter.waitForShared().perform(.saveStageAsGroup(name: name))
        return .result()
    }
}

/// 検索の欄を出す
struct OpenSearchIntent: AppIntent {
    static let title: LocalizedStringResource = "ウインドウ・グループを検索"
    static let description = IntentDescription("Pinstage の検索の欄を出します。")

    @MainActor
    func perform() async throws -> some IntentResult {
        try await AutomationCenter.waitForShared().perform(.search)
        return .result()
    }
}

// MARK: - Siri・Spotlight から呼び出せる言い方

nonisolated struct PinstageShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecallGroupIntent(),
            phrases: [
                "\(.applicationName) でグループを呼び出す",
                "\(.applicationName) で \(\.$group) を呼び出す",
            ],
            shortTitle: "グループを呼び出す",
            systemImageName: "square.stack.3d.up"
        )
        AppShortcut(
            intent: SetStripIntent(),
            phrases: ["\(.applicationName) のストリップを切り替える"],
            shortTitle: "ストリップを出す・隠す",
            systemImageName: "sidebar.left"
        )
        AppShortcut(
            intent: OpenSearchIntent(),
            phrases: ["\(.applicationName) で検索する"],
            shortTitle: "検索",
            systemImageName: "magnifyingglass"
        )
    }
}
