## ダウンロードと開き方

1. 下の `Pinstage-<版>.dmg` をダウンロードして開き、`Pinstage` を `Applications`（アプリケーションフォルダ）へドラッグします（`.zip` は展開して `Pinstage.app` を入れる形です。中身は同じ）
2. Pinstage を開くと「開発元を確認できない」と止められます（Apple の公証を受けていないため）。次のどちらかで開けます
   - システム設定 →「プライバシーとセキュリティ」の下の方にある「このまま開く」を押す
   - ターミナルで `xattr -dr com.apple.quarantine /Applications/Pinstage.app` を実行してから開く
3. 初めて開くと「アクセシビリティ」の許可を求められます。システム設定で Pinstage をオンにしてください（ほかのアプリのウインドウを動かす・前に出すために使います）
   - ウインドウバーの形式を「サムネイル」にしたときだけ、「画面収録」の許可も求められます（使わなければ不要です）
4. メニューバーに Pinstage のアイコンが出て、画面の左端にウインドウバーが出ます。macOS のステージマネージャはオフにしてください（オンだと、並べたとおりになりません）

新しい版に入れ替えたときは、アクセシビリティ（と画面収録）の許可を取り直す必要があります（システム設定の一覧で古い Pinstage を「−」で消してから、もう一度許可してください）。

macOS 26 以降が必要です。Intel と Apple Silicon のどちらの Mac でも動きます。

ソースからビルドする方法は [README](https://github.com/yzanbo/pinstage#readme) を見てください。

---

**English:** Requires macOS 26 or later. Download the dmg (or zip), drag `Pinstage.app` to Applications, then allow it in System Settings → Privacy & Security ("Open Anyway"), or run `xattr -dr com.apple.quarantine /Applications/Pinstage.app`. Grant Accessibility permission when asked (Screen Recording is only needed for thumbnails). The app is ad-hoc signed and not notarized, so you will need to grant the permissions again after each update. Turn off macOS Stage Manager while using Pinstage.
