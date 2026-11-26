## この版の変更（0.3.0）

<!-- 出すたびに、この版の変更に書き直す（make publish が、リリースの説明の先頭と、アプリの中の更新の画面に入れる） -->

### 新しくできること

- **アプリの中から、新しい版に更新できるようにしました**：1 時間に 1 回、新しい版がないかを確かめ、見つけると、メニューバーのアイコンの右下に下向きの矢印の印を付け、メニューのいちばん上の「新しいバージョン … があります…」で知らせます（画面には割り込みません）。印は、新しい版を入れるか「このバージョンはスキップ」を選ぶまで残ります。メニューの「アップデートを確認…」でも、すぐに確かめられます。自動で確かめるかは、設定の「一般」→「アップデート」で切り替えられます
- **更新しても、許可を取り直さずに済むようにしました**：配る版を、作者の決まった証明書で署名するようにしました。次からの更新では、アクセシビリティ（と画面収録）の許可がそのまま引き継がれ、「このまま開く」も要りません

### 気をつけること

- 0.2.2 までの版にはこの機能がなく、署名のしかたも違うので、この版へは、ダウンロードして手で入れ替えてください。そのとき 1 回だけ、アクセシビリティ（と画面収録）の許可を取り直します（システム設定の一覧で古い Pinstage を「−」で消してから、もう一度許可します）。次の版からは、アプリの中で届きます
- 新しい版の確認とダウンロードのときだけ、GitHub に接続します。更新ファイルは、作者の鍵の署名を確かめてから入れます

**English:** Pinstage can now update itself: it checks for new versions every hour and shows a down-arrow badge at the bottom right of the menu bar icon until you install the update or skip that version (or use "アップデートを確認…" in the menu). Releases are now signed with the author's self-signed certificate, so Accessibility and Screen Recording permissions are kept across updates. Updating from 0.2.2 or earlier requires one manual install and granting the permissions again.
