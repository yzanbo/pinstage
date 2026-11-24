import Foundation

/// ストリップを出すか隠すか
public enum StripVisibility: String, CaseIterable, Codable, Sendable {
    case show
    case hide
    case toggle
}

/// 外から頼まれる操作（URL・「ショートカット」アプリ）
public enum PinstageCommand: Equatable, Sendable {
    /// グループを呼び出す（グループの名前か ID）
    case recallGroup(String)
    case nextGroup
    case previousGroup
    case strip(StripVisibility)
    case search
    /// ステージをグループとして保存する（名前がなければ仮の名前）
    case saveStageAsGroup(name: String?)
}

/// Pinstage の URL（pinstage://…）
///
/// - pinstage://group/開発 … 「開発」グループを呼び出す（名前の代わりにグループの ID でもよい）
/// - pinstage://group/next ・ pinstage://group/previous … 次・前のグループ
/// - pinstage://strip/show ・ hide ・ toggle … ストリップを出す・隠す・切り替える
/// - pinstage://search … 検索の欄を出す
/// - pinstage://save?name=資料作り … ステージをグループとして保存する
public enum PinstageURL {
    public static let scheme = "pinstage"

    public static func parse(_ url: URL) -> PinstageCommand? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // pinstage://group/開発 では host が "group"、path が "/開発"
        let action = (url.host(percentEncoded: false) ?? "").lowercased()
        let argument = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch action {
        case "group":
            switch argument.lowercased() {
            case "": return nil
            case "next": return .nextGroup
            case "previous", "prev": return .previousGroup
            default: return .recallGroup(argument)
            }
        case "strip":
            return StripVisibility(rawValue: argument.lowercased()).map(PinstageCommand.strip) ?? (argument.isEmpty ? .strip(.toggle) : nil)
        case "search":
            return .search
        case "save":
            let name = components?.queryItems?.first(where: { $0.name == "name" })?.value
            return .saveStageAsGroup(name: name.flatMap(GroupNaming.normalized))
        default:
            return nil
        }
    }

    /// グループを呼び出す URL（名前を URL に使える形にする）
    public static func groupURL(name: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "group"
        components.path = "/" + name
        return components.url
    }
}

extension StageLibrary {
    /// 名前か ID でグループを探す（ID → 名前がぴったり同じ → 大文字小文字・全角半角・ひらがなカタカナの違いを除いて同じ、の順）
    public func group(matching key: String) -> StageGroup? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let id = UUID(uuidString: trimmed), let group = group(id: id) { return group }
        if let group = groups.first(where: { $0.name == trimmed }) { return group }
        let normalized = SearchMatcher.normalize(trimmed)
        return groups.first { SearchMatcher.normalize($0.name) == normalized }
    }
}
