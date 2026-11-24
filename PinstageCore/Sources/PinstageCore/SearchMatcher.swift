import Foundation

/// 検索に出すもの（ウインドウ・グループ）
public struct SearchItem<ID: Hashable>: Equatable {
    public var id: ID
    /// 名前（ウインドウ名・グループ名）
    public var title: String
    /// 添える名前（アプリ名・グループの中身のアプリ名など）
    public var subtitle: String

    public init(id: ID, title: String, subtitle: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

/// 打った言葉で、ウインドウ・グループを絞り込んで並べる
///
/// - 空白で区切った言葉は、すべてを含むものだけに絞る（名前か添える名前のどちらかに含めばよい）
/// - 大文字と小文字・全角と半角・ひらがなとカタカナ・濁点の有無は区別しない
/// - 名前の頭に合うもの → 名前に含むもの → 添える名前に合うもの、の順に上へ。同じなら、渡した順のまま
public enum SearchMatcher {
    /// 比べやすい形にする（大文字小文字・全角半角・ひらがなカタカナをそろえる）
    public static func normalize(_ text: String) -> String {
        let katakana = text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text
        return katakana.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ja_JP"))
    }

    /// 打った言葉を、空白で区切って比べやすい形にする
    public static func terms(_ query: String) -> [String] {
        normalize(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// 合い方の点（合わなければ nil）。大きいほど上に並べる
    public static func score<ID>(_ item: SearchItem<ID>, terms: [String]) -> Int? {
        let title = normalize(item.title)
        let subtitle = normalize(item.subtitle)
        var total = 0
        for term in terms {
            if title.hasPrefix(term) {
                total += 30
            } else if title.contains(term) {
                total += 20
            } else if subtitle.hasPrefix(term) {
                total += 15
            } else if subtitle.contains(term) {
                total += 10
            } else {
                return nil
            }
        }
        return total
    }

    /// 絞り込んで並べる（言葉が空なら、渡した順のまますべて）
    public static func results<ID>(query: String, items: [SearchItem<ID>]) -> [SearchItem<ID>] {
        let terms = terms(query)
        guard !terms.isEmpty else { return items }
        return items.enumerated()
            .compactMap { offset, item in score(item, terms: terms).map { (offset, item, $0) } }
            .sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }
            .map(\.1)
    }
}
