/// 順に切り替える計算（次のグループ・前のウインドウなど）
public enum Cycling {
    /// current の次（forward が false なら前）の番号。端まで行ったら反対の端に戻る。
    /// current がなければ、次なら先頭、前なら最後
    public static func index(after current: Int?, count: Int, forward: Bool) -> Int? {
        guard count > 0 else { return nil }
        guard let current, (0..<count).contains(current) else { return forward ? 0 : count - 1 }
        return (current + (forward ? 1 : count - 1)) % count
    }
}
