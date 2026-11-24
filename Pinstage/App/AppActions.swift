import PinstageCore

/// 押されたときにすること（設定画面・型の編集画面を開くなど。ストリップの中身から呼ぶ）
final class AppActions {
    var openSettings: (SettingsTab?) -> Void = { _ in }
    /// 型の編集画面で、新しい型を作る（並びがあれば、そこから始める）
    var createLayout: ([UnitRect]) -> Void = { _ in }
    /// 検索の欄を出す
    var openSearch: () -> Void = {}
    /// グループの編集画面を開く
    var editGroup: (StageGroup) -> Void = { _ in }
}
