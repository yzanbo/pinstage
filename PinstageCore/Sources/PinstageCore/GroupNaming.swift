/// グループと型の仮の名前
public enum GroupNaming {
    /// グループの名前の頭
    public static let groupPrefix = "グループ"
    /// 登録した型の名前の頭
    public static let layoutPrefix = "マイ型"

    /// 「グループ 1」「グループ 2」… のうち、まだ使っていないいちばん小さい番号の名前
    public static func nextName(prefix: String = groupPrefix, existing: [String]) -> String {
        let used = Set(existing)
        var number = 1
        while used.contains("\(prefix) \(number)") { number += 1 }
        return "\(prefix) \(number)"
    }

    /// 入力された名前を整える（前後の空白を除き、空なら nil）
    public static func normalized(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
