DERIVED_DATA := build/DerivedData
APP := $(DERIVED_DATA)/Build/Products/Debug/Pinstage.app
RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/Pinstage.app
# アプリの識別名（Launch Services に、まだ動いていると思われていないかを調べるのに使う）
BUNDLE_ID := app.pinstage.Pinstage
# make install で入れる場所
INSTALL_DIR ?= /Applications
# アプリの版（project.yml の CFBundleShortVersionString）。1.0.0 より前は β 版
VERSION := $(shell sed -n 's/.*CFBundleShortVersionString: *"\(.*\)"/\1/p' project.yml)
# β 版として出すときは BETA=1 のように番号を渡す（タグは v0.1.0-beta.1、GitHub ではプレリリースにする）
BETA ?=
RELEASE_NAME := $(VERSION)$(if $(BETA),-beta.$(BETA))
DIST_BASE := dist/Pinstage-$(RELEASE_NAME)
DIST_ZIP := $(DIST_BASE).zip
DIST_DMG := $(DIST_BASE).dmg

# 署名の証明書の名前（make cert で一度だけ作る）。あれば開発用のビルドもこれで署名する（なければその場の署名＝アドホック署名）。
# 毎回同じ証明書で署名すると、ビルドし直しても macOS から同じアプリと見なされ、アクセシビリティの許可が外れない
CERT_NAME := Pinstage Dev
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q '"$(CERT_NAME)"' && echo "$(CERT_NAME)" || echo "-")
# 配る版に署名する証明書（作者の「Pinstage Dev」）の SHA-1。作り直した証明書は、名前が同じでも別物なので、
# 配る版と更新の試験は、名前ではなくこの値で確かめる（docs/ARCHITECTURE.md の「署名と更新」）
DIST_CERT_SHA1 := E47EC4DDC09E7188A1C4CBF6B7FBBDD25BFAF4F5
# 配る版の証明書が、この Mac のキーチェーンにあるかを確かめる（なければ、案内を出して止める）
require_dist_cert = security find-identity -v -p codesigning 2>/dev/null | grep -qi "$(DIST_CERT_SHA1)" || { \
	echo "配る版に署名する証明書（「$(CERT_NAME)」・SHA-1 $(DIST_CERT_SHA1)）が、この Mac のキーチェーンにありません。" >&2; \
	echo "証明書の控え（.p12）を取り込んでください。作り直した証明書は別物なので使えません（入れてもらったアプリの許可が外れるため）。" >&2; \
	exit 1; }
# Launch Services（アプリの場所とアイコンを覚えている macOS の仕組み）に、アプリを登録し直す道具
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# $(call register_app,アプリの場所): アプリを Launch Services に登録し直す（失敗しても止めない）
register_app = touch "$(1)"; $(LSREGISTER) -f "$(1)" >/dev/null 2>&1 || true
# xcodebuild に足す引数（ふだんは空）
XCODEBUILD_FLAGS ?=
# swift test に足す引数（ふだんは空）
SWIFT_TEST_FLAGS ?=

XCODEBUILD := xcodebuild -project Pinstage.xcodeproj -scheme Pinstage -sdk macosx \
	-derivedDataPath $(DERIVED_DATA) CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" $(XCODEBUILD_FLAGS)

# 更新の仕組み（Sparkle）。公式の配布物を取り寄せて Vendor/Sparkle に置く（リポジトリには入れない。Pinshelf と同じ版）。
# 版を上げるときは、SPARKLE_VERSION と SPARKLE_SHA256（配布物 Sparkle-版.tar.xz の SHA-256）を一緒に変える
SPARKLE_VERSION := 2.10.1
SPARKLE_SHA256 := 1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
SPARKLE_DIR := Vendor/Sparkle
# 取り寄せた版の印（版を上げると名前が変わり、取り寄せ直す）
SPARKLE_STAMP := $(SPARKLE_DIR)/.version-$(SPARKLE_VERSION)
# 更新ファイルの署名を確かめる公開鍵（project.yml の SUPublicEDKey。Pin シリーズで共通の鍵）
UPDATE_PUBLIC_KEY := $(shell sed -n 's/^ *SUPublicEDKey: *"\(.*\)"/\1/p' project.yml)
# 配る更新ファイル（zip）を置く場所。版の一覧（appcast.xml）の中のダウンロード元になる
RELEASE_DOWNLOAD_URL := https://github.com/yzanbo/pinstage/releases/download/v$(RELEASE_NAME)/

.PHONY: generate build release dist publish publish-check run stop install uninstall test clean cert icon preview readme-images \
	sparkle update-test update-test-log

# アイコンを描くスクリプトをビルドする場所
ICON_TOOL_DIR := $(DERIVED_DATA)/icon-tool

# project.yml から Pinstage.xcodeproj を作る（ファイルを足したときも、これで入る）
generate: $(SPARKLE_STAMP)
	xcodegen generate

# Sparkle（更新の仕組み）を取り寄せる。ビルドの前に自動で行うので、ふだんは自分で呼ばなくてよい。
# 取り寄せたファイルは、決めてある SHA-256 と合うことを確かめてから使う（合わなければ止まる）
sparkle: $(SPARKLE_STAMP)

$(SPARKLE_STAMP):
	rm -rf "$(SPARKLE_DIR)"
	mkdir -p "$(SPARKLE_DIR)"
	curl -fsSL -o "$(SPARKLE_DIR)/Sparkle.tar.xz" \
		"https://github.com/sparkle-project/Sparkle/releases/download/$(SPARKLE_VERSION)/Sparkle-$(SPARKLE_VERSION).tar.xz"
	echo "$(SPARKLE_SHA256)  $(SPARKLE_DIR)/Sparkle.tar.xz" | shasum -a 256 -c -
	@# 使うものだけ取り出す: アプリに入れるフレームワーク・署名と版の一覧の道具・ライセンス
	tar -xJf "$(SPARKLE_DIR)/Sparkle.tar.xz" -C "$(SPARKLE_DIR)" ./Sparkle.framework ./bin ./LICENSE
	rm "$(SPARKLE_DIR)/Sparkle.tar.xz"
	@# Sparkle のライセンスは、配るものに全文を含める決まりなので、アプリに同梱するファイルへ写す（リポジトリに入れる）
	mkdir -p Pinstage/Licenses
	cp "$(SPARKLE_DIR)/LICENSE" Pinstage/Licenses/Sparkle.txt
	touch "$@"

# 開発用（Debug）にビルドする
build: generate
	@echo "署名: $(SIGN_IDENTITY)"
	$(XCODEBUILD) -configuration Debug build

# 配布用（Release）にビルドする。Intel と Apple Silicon の両方で動く形にする
release: generate
	@echo "署名: $(SIGN_IDENTITY)"
	$(XCODEBUILD) -configuration Release ONLY_ACTIVE_ARCH=NO build

# GitHub の Releases に置く DMG と zip を作る（dist/Pinstage-版.dmg・.zip・.sha256）。
# DMG は、開くと Pinstage.app とアプリケーションフォルダが並び、ドラッグで入れられる形にする。
# 配る版は、決まった自己署名の証明書で署名する（更新しても許可が引き継がれるように。docs/ARCHITECTURE.md の「署名と更新」）
dist:
	@$(require_dist_cert)
	$(MAKE) release SIGN_IDENTITY="$(CERT_NAME)"
	@# 署名が壊れていないかと、macOS が許可を結び付ける条件（指定要件）が、配る版の証明書になっているかを確かめる
	codesign --verify --deep --strict "$(RELEASE_APP)"
	@codesign -d -r- "$(RELEASE_APP)" 2>&1 | grep -qi 'certificate leaf = H"$(DIST_CERT_SHA1)"' || \
		{ echo "$(RELEASE_APP) が、配る版の証明書（SHA-1 $(DIST_CERT_SHA1)）で署名されていません。" >&2; exit 1; }
	mkdir -p dist
	ditto -c -k --sequesterRsrc --keepParent "$(RELEASE_APP)" "$(DIST_ZIP)"
	rm -rf dist/dmg-root
	mkdir -p dist/dmg-root
	ditto "$(RELEASE_APP)" dist/dmg-root/Pinstage.app
	ln -s /Applications dist/dmg-root/Applications
	@# macOS 26 以降は diskutil image で作る（hdiutil create は「使わなくなる」と警告が出るため）。ない版では hdiutil で作る
	rm -f "$(DIST_DMG)"
	if diskutil image create from -h >/dev/null 2>&1; then \
		diskutil image create from --format UDZO --volumeName "Pinstage" dist/dmg-root "$(DIST_DMG)"; \
	else \
		hdiutil create -volname "Pinstage" -srcfolder dist/dmg-root -ov -format UDZO "$(DIST_DMG)"; \
	fi
	rm -rf dist/dmg-root
	cd dist && shasum -a 256 "Pinstage-$(RELEASE_NAME).dmg" "Pinstage-$(RELEASE_NAME).zip" > "Pinstage-$(RELEASE_NAME).sha256"
	@echo ""
	@echo "$(DIST_DMG) と $(DIST_ZIP) を作りました（版: $(RELEASE_NAME)）"

# DMG と zip を作り、GitHub に Release（タグ v版）を作ってアップロードする（GitHub CLI を使う）。
# 説明は「この版の変更」（scripts/release-changes.md。出すたびに書き直す）と「ダウンロードと開き方」をつなげる。
# β 版のときは、説明の先頭に β 版の注意を付け、プレリリースにする。
#
# 入れてもらったアプリに更新を届けるため、zip に EdDSA の鍵で署名して、版の一覧を dist/appcast.xml に作る。
# Release を作れたら appcast.xml に写し、それだけをコミットしてプッシュする（アプリは、main の appcast.xml を見て新しい版を知る。
# 先に書き換えると、Release を作れずに止まったときに、appcast.xml が書き換わったまま残るため）
publish: publish-check dist
	( $(if $(BETA),cat scripts/release-notes-beta.md; echo;) cat scripts/release-changes.md; echo; cat scripts/release-notes.md ) > dist/release-notes.md
	./scripts/make-appcast.sh "$(DIST_ZIP)" scripts/release-changes.md "$(RELEASE_DOWNLOAD_URL)" dist/appcast.xml
	gh release create "v$(RELEASE_NAME)" "$(DIST_DMG)" "$(DIST_ZIP)" "$(DIST_BASE).sha256" \
		--target main --title "Pinstage $(RELEASE_NAME)$(if $(BETA), (β 版))" $(if $(BETA),--prerelease) \
		--notes-file dist/release-notes.md
	cp dist/appcast.xml appcast.xml
	git add appcast.xml
	git commit -q -m "chore: 版の一覧（appcast）を $(RELEASE_NAME) にする" -- appcast.xml
	git push origin main
	@echo ""
	@echo "$(RELEASE_NAME) を公開しました。入れてもらったアプリには、appcast.xml を通して新しい版が届きます。"

# 公開の前に、更新ファイルの署名の鍵と Git の状態を確かめる（そろっていなければ、何も作らずに止める。中身は scripts/publish-check.sh）。
# 配る版の証明書は、続く make dist の初めに確かめる
publish-check: $(SPARKLE_STAMP)
	./scripts/publish-check.sh "$(UPDATE_PUBLIC_KEY)" "$(RELEASE_NAME)"

# 更新を、手元で通しで試す（docs/TESTING.md の「更新を通しで試す」）。
# ふだんの Pinstage とは別の ID の試験用アプリを、配る版と同じ証明書で 2 つの版に作り、新しい版を手元のサーバーから配る（止めるときは control + C）。
# アドホック署名どうしで比べたいときは、make update-test SIGN_IDENTITY=- のように渡す。
# 手元のサーバーのポートは、Pin シリーズの試験どうしでぶつからないよう、アプリごとに分ける（Pinshelf 8765・Pinshot 8766・Pinstage 8767）。
# ほかで使っているときは make update-test UPDATE_TEST_PORT=8800 のように替える
UPDATE_TEST_PORT ?= 8767
update-test: SIGN_IDENTITY = $(CERT_NAME)
update-test: generate
	@if [ "$(SIGN_IDENTITY)" = "$(CERT_NAME)" ]; then $(require_dist_cert); fi
	SIGN_IDENTITY="$(SIGN_IDENTITY)" UPDATE_TEST_PORT="$(UPDATE_TEST_PORT)" ./scripts/update-test.sh $(XCODEBUILD_FLAGS)

# 更新の試験のあいだの macOS の記録を、build/update-test/system.log に書き出す
# （許可が引き継がれたか・確認の画面が出たかの裏取りと、うまくいかないときの手がかりに使う）。
# いつからの記録かは SINCE="2026-11-26 19:50:00" のように渡す（なければ、直近 30 分）
update-test-log:
	./scripts/update-test-log.sh

# 動いている Pinstage を終了してから、ビルドした新しい版を起動する。
# 終了した直後は、Launch Services がまだ「動いている」と思っていて、open が
# 「_LSOpenURLsWithCompletionHandler() failed with error -600」で失敗することがあるので、少し待ってやり直す
run: build stop
	@$(call register_app,$(APP))
	@for i in 1 2 3 4 5; do open "$(APP)" 2>/dev/null && exit 0; sleep 0.5; done; open "$(APP)"

# 動いている Pinstage を終了する（最大 5 秒待つ）。そのあと、Launch Services がアプリの終了に気づくまで（最大 3 秒）待つ
stop:
	-@killall Pinstage 2>/dev/null; \
	for i in $$(seq 1 50); do pgrep -x Pinstage >/dev/null || break; sleep 0.1; done; \
	for i in $$(seq 1 30); do lsappinfo find bundleid=$(BUNDLE_ID) | grep -q . || break; sleep 0.1; done

# 配布用にビルドして、アプリケーションフォルダに入れる（前の版は置き換える）
install: release stop
	mkdir -p "$(INSTALL_DIR)/Pinstage.app"
	rsync -a --delete "$(RELEASE_APP)/" "$(INSTALL_DIR)/Pinstage.app/"
	@$(call register_app,$(INSTALL_DIR)/Pinstage.app)
	@echo ""
	@echo "$(INSTALL_DIR)/Pinstage.app に入れました。アプリケーションフォルダから Pinstage を開いてください。"

# アプリケーションフォルダから Pinstage を消す（グループと設定は残る）
uninstall: stop
	rm -rf "$(INSTALL_DIR)/Pinstage.app"

# テストを動かす（アプリは起動しない）
test:
	cd PinstageCore && swift test $(SWIFT_TEST_FLAGS)

clean:
	rm -rf $(DERIVED_DATA) PinstageCore/.build build/update-test

# 画面の見た目を、見本のデータで画像に描き出す（アプリを起動せずに見た目を確かめる。build/preview に書き出す）。
# ストリップ（見た目ごと。左に置いたとき・下に置いたとき・アイコンの並びを 1 列まで狭めたとき）と、グループの編集画面・型の編集画面・検索・設定のタブ（一般・ウインドウバー・ウインドウスイッチャー・型・ショートカット・自動化）
PREVIEW_LOOKS := grid gridLarge list listLarge thumbnail thumbnailLarge
PREVIEW_VIEWS := groupEditor layoutEditor search desktopPicker desktopOverview desktopOverviewIcons desktopOverviewThumbnails desktopDisplayGroups layouts general strip switcher shortcuts automation
preview: build
	mkdir -p build/preview
	@for look in $(PREVIEW_LOOKS); do \
		"$(APP)/Contents/MacOS/Pinstage" --render-strip-preview "build/preview/strip-$$look.png" $$look 230 >/dev/null 2>&1; \
		"$(APP)/Contents/MacOS/Pinstage" --render-strip-preview "build/preview/strip-bottom-$$look.png" $$look 1280 normal bottom >/dev/null 2>&1; \
	done
	@for look in grid gridLarge; do \
		"$(APP)/Contents/MacOS/Pinstage" --render-strip-preview "build/preview/strip-$$look-1column.png" $$look 52 >/dev/null 2>&1; \
	done
	@for view in $(PREVIEW_VIEWS); do \
		"$(APP)/Contents/MacOS/Pinstage" --render-view-preview "build/preview/view-$$view.png" $$view >/dev/null 2>&1; \
	done
	@"$(APP)/Contents/MacOS/Pinstage" --render-strip-preview "build/preview/strip-desktopDisplayGroups.png" grid 230 desktopDisplayGroups >/dev/null 2>&1
	@echo "build/preview に書き出しました"

# README の見本の画像を作り直す（見た目を変えたとき。docs/images に書き出す。Pinshelf・Pinshot と同じ考え方）。
# ウインドウバーとウインドウスイッチャーは、make preview と同じく、開発用のビルドで見本のデータを描く（画面には出さない）
readme-images: build
	"$(APP)/Contents/MacOS/Pinstage" --render-readme-images docs/images

# アプリのアイコンを描き直す（scripts/make-app-icon.swift を変えたとき。Pinstage/Assets.xcassets に書き出す）
icon:
	mkdir -p $(ICON_TOOL_DIR)
	swiftc -O -module-cache-path $(ICON_TOOL_DIR)/cache scripts/make-app-icon.swift -o $(ICON_TOOL_DIR)/make-app-icon
	$(ICON_TOOL_DIR)/make-app-icon

# 署名の証明書「Pinstage Dev」を作る（一度だけ。途中でパスワードを聞かれる）。
# 開発用のビルドと、配る版（make dist）の両方に使う
cert:
	./scripts/create-dev-cert.sh
