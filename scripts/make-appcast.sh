#!/bin/bash
# 版の一覧（appcast.xml）を作る（make publish・make update-test が呼ぶ）。
#
# Sparkle の道具（generate_appcast）が、更新ファイル（zip）に EdDSA の鍵で署名し、zip の中のアプリから版を読み、
# この版の変更（Markdown）を埋め込んで、appcast.xml を書き出す。載せるのは、いちばん新しい版だけ（Sparkle が見るのは、それで足りる）。
#
# 使い方: make-appcast.sh <更新ファイル.zip> <この版の変更.md> <ダウンロード元の URL の頭> <書き出す appcast.xml>
#   環境変数 SPARKLE_KEY_FILE: 秘密鍵のファイル（試験用）。なければ、ログインキーチェーンの鍵を使う
set -euo pipefail

ZIP="$1"
NOTES="$2"
URL_PREFIX="$3"
OUTPUT="$4"
BIN="Vendor/Sparkle/bin"

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

NAME="$(basename "${ZIP}" .zip)"
cp "${ZIP}" "${STAGE}/${NAME}.zip"
# この版の変更から、HTML のコメント（書き方の覚え書き）の行を除いて、zip と同じ名前で置く（generate_appcast が、同じ名前の .md を拾う）
grep -v '^<!--.*-->$' "${NOTES}" > "${STAGE}/${NAME}.md"

KEY_ARGS=()
if [ -n "${SPARKLE_KEY_FILE:-}" ]; then
  KEY_ARGS=(--ed-key-file "${SPARKLE_KEY_FILE}")
fi

# macOS の bash（3.2）は、空の配列をそのまま展開すると止まるので、あるときだけ展開する
"${BIN}/generate_appcast" ${KEY_ARGS[@]+"${KEY_ARGS[@]}"} \
  --download-url-prefix "${URL_PREFIX}" --embed-release-notes --link "https://github.com/yzanbo/pinstage" \
  -o "${STAGE}/appcast.xml" "${STAGE}"

# 署名とダウンロード元が入ったことを確かめてから、書き出す
if ! grep -q 'sparkle:edSignature="' "${STAGE}/appcast.xml" || ! grep -q "url=\"${URL_PREFIX}${NAME}.zip\"" "${STAGE}/appcast.xml"; then
  echo "appcast.xml に、署名かダウンロード元が入りませんでした。" >&2
  exit 1
fi
cp "${STAGE}/appcast.xml" "${OUTPUT}"
echo "版の一覧を書き出しました: ${OUTPUT}"
