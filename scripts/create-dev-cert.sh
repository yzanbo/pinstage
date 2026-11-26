#!/bin/bash
# 開発用のコード署名の証明書「Pinstage Dev」を、ログインキーチェーンに作る。
#
# アドホック署名だと、ビルドし直すたびに macOS から「別のアプリ」と見なされ、
# アクセシビリティの許可が外れ、許可し直す必要がある。
# 毎回同じ証明書で署名すれば、ビルドし直しても同じアプリのまま扱われる。
# 途中で、キーチェーンの変更を許可するためのパスワードを聞かれる。
# （Pinshot・Pinshelf の scripts/create-dev-cert.sh と同じ作り）
set -euo pipefail

NAME="Pinstage Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# 全角の文字のすぐ前の変数は、${NAME} と波かっこで囲む（macOS の bash 3.2 は、言語の設定が UTF-8 のとき、
# 続く全角の文字のバイトまで変数名として読み、「NAME�: unbound variable」で止まるため）
if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "「${NAME}」の証明書はすでにあります。"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# macOS 標準の openssl（LibreSSL）を使う（キーチェーンが読める形式で書き出すため）
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null
/usr/bin/openssl pkcs12 -export -name "$NAME" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/cert.p12" -passout pass:pinstage

security import "$WORK/cert.p12" -k "$KEYCHAIN" -P pinstage -T /usr/bin/codesign
# コード署名に使う証明書として信頼する（ここでパスワードを聞かれる）
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo
echo "「${NAME}」の証明書を作りました。make run でビルドすると、この証明書で署名されます。"
