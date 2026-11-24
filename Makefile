DERIVED_DATA := build/DerivedData
APP := $(DERIVED_DATA)/Build/Products/Debug/Pinstage.app
RELEASE_APP := $(DERIVED_DATA)/Build/Products/Release/Pinstage.app
# アプリの識別名（Launch Services に、まだ動いていると思われていないかを調べるのに使う）
BUNDLE_ID := app.pinstage.Pinstage
# make install で入れる場所
INSTALL_DIR ?= /Applications

# 「Pinstage Dev」の証明書があればそれで署名する（なければその場の署名＝アドホック署名）。
# 毎回同じ証明書で署名すると、ビルドし直しても macOS から同じアプリと見なされ、
# アクセシビリティの許可が外れない（make cert で一度だけ作る）
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q '"Pinstage Dev"' && echo "Pinstage Dev" || echo "-")
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

.PHONY: generate build release run stop install uninstall test clean cert icon preview

# アイコンを描くスクリプトをビルドする場所
ICON_TOOL_DIR := $(DERIVED_DATA)/icon-tool

# project.yml から Pinstage.xcodeproj を作る（ファイルを足したときも、これで入る）
generate:
	xcodegen generate

# 開発用（Debug）にビルドする
build: generate
	@echo "署名: $(SIGN_IDENTITY)"
	$(XCODEBUILD) -configuration Debug build

# 配布用（Release）にビルドする。Intel と Apple Silicon の両方で動く形にする
release: generate
	@echo "署名: $(SIGN_IDENTITY)"
	$(XCODEBUILD) -configuration Release ONLY_ACTIVE_ARCH=NO build

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
	rm -rf $(DERIVED_DATA) PinstageCore/.build

# 画面の見た目を、見本のデータで画像に描き出す（アプリを起動せずに見た目を確かめる。build/preview に書き出す）。
# ストリップ（見た目ごと）と、グループの編集画面・型の編集画面・検索・設定の「型」
PREVIEW_LOOKS := icons grid list thumbnail
PREVIEW_VIEWS := groupEditor layoutEditor search layouts
preview: build
	mkdir -p build/preview
	@for look in $(PREVIEW_LOOKS); do \
		"$(APP)/Contents/MacOS/Pinstage" --render-strip-preview "build/preview/strip-$$look.png" $$look 230 >/dev/null 2>&1; \
	done
	@for view in $(PREVIEW_VIEWS); do \
		"$(APP)/Contents/MacOS/Pinstage" --render-view-preview "build/preview/view-$$view.png" $$view >/dev/null 2>&1; \
	done
	@echo "build/preview に書き出しました"

# アプリのアイコンを描き直す（scripts/make-app-icon.swift を変えたとき。Pinstage/Assets.xcassets に書き出す）
icon:
	mkdir -p $(ICON_TOOL_DIR)
	swiftc -O -module-cache-path $(ICON_TOOL_DIR)/cache scripts/make-app-icon.swift -o $(ICON_TOOL_DIR)/make-app-icon
	$(ICON_TOOL_DIR)/make-app-icon

# 開発用の署名の証明書「Pinstage Dev」を作る（一度だけ。途中でパスワードを聞かれる）
cert:
	./scripts/create-dev-cert.sh
