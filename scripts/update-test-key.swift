// 更新の通しの試験に使う、その場かぎりの EdDSA の鍵を作る（make update-test が使う）。
// 1 行目に秘密鍵（32 バイトの種）、2 行目に公開鍵を、base64 で出す。
// キーチェーンには入れない（リリース用の鍵とは別物。試験用のアプリにしか使わない）
import CryptoKit
import Foundation

let key = Curve25519.Signing.PrivateKey()
print(key.rawRepresentation.base64EncodedString())
print(key.publicKey.rawRepresentation.base64EncodedString())
