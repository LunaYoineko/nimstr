# Nimstr

Nostr 用 Nim SDK。鍵生成、イベントの署名・送信、リレー接続、Bech32 エンコードなどをサポートします。

## 特徴

- **鍵管理** — 秘密鍵・公開鍵の生成、nsec/npub 形式のエンコード
- **イベント署名** — Schnorr 署名 (secp256k1) によるイベントの署名・検証
- **リレー接続** — WebSocket 経由で Nostr リレーに接続
- **イベント送信** — テキストノート (kind 1)、返信、プロフィール更新 (kind 0)、削除 (kind 5)
- **サブスクリプション** — フィルターによるイベント購読 (REQ/CLOSE)
- **Bech32** — nsec, npub エンコード・デコード
- **リレープール** — 複数リレーへの同時接続・ブロードキャスト

## インストール

```bash
# 1. プロジェクト作成
mkdir myapp && cd myapp
nimble init

# 2. nimstr をインストール
nimble install https://github.com/LunaYoineko/nimstr

# 3. .nimble ファイルに依存関係を追記
# myapp.nimble の dependencies セクションに以下を追加:
#   requires "nimstr"

# 5. コンパイル・実行
nim c -r src/myapp.nim
```

**注意**: 依存関係（ws, secp256k1, nimSHA2）は `requires "nimstr"` だけで自動的に解決されます。SSL が必要な場合は利用側の `config.nims` にも `switch("define", "ssl")` を記述してください。

## クイックスタート

```nim
import std/asyncdispatch
import nimstr

proc main() {.async.} =
  # 鍵を生成
  let keypair = generateKeypair()
  echo "npub: ", keypair.npub
  echo "nsec: ", keypair.nsec

  # リレーに接続
  let relay = newRelayClient("wss://relay.damus.io")
  await relay.connect()

  # テキストノートを送信
  let ok = await relay.sendTextNote(keypair.seckeyHex, "Hello, Nostr!")
  echo "Sent: ", ok

  # 閉じる
  await relay.close()

waitFor main()
```

## API

### 鍵生成・復元

| 関数 | 説明 |
|---|---|
| `generateKeypair()` | 新しい鍵ペアを生成。`NostrKeypair` (seckeyHex, pubkeyHex, nsec, npub) を返す |
| `keypairFromSecret(secretInput: string)` | 16進数の秘密鍵または nsec から鍵ペアを復元 |

```nim
let kp = generateKeypair()
echo kp.npub  # npub1...

let restored = keypairFromSecret(kp.nsec)
assert restored.pubkeyHex == kp.pubkeyHex
```

### リレー接続

| 関数 | 説明 |
|---|---|
| `newRelayClient(url: string)` | 単一リレークライアントを作成 |
| `newRelayPool(urls: seq[string])` | 複数リレークライアントを作成 |
| `connect(relay)` | リレーに WebSocket 接続 |
| `connectAll(pool)` | プール内の全リレーに接続 |
| `close(relay)` / `closeAll(pool)` | 切断 |

```nim
# 単一リレー
let relay = newRelayClient("wss://relay.damus.io")
await relay.connect()

# リレープール
let pool = newRelayPool(@[
  "wss://relay.damus.io",
  "wss://nos.lol"
])
await pool.connectAll()
```

### イベント操作

#### テキストノート (kind 1)

```nim
# 単一リレーへ送信
let ok = await relay.sendTextNote(seckeyHex, "Hello, Nostr!")

# 全リレーへブロードキャスト
let count = await pool.sendTextNoteAll(seckeyHex, "Hello, Nostr!")
```

#### 返信 (kind 1 + タグ)

```nim
let replyTarget = ReplyTarget(
  eventId: "previous-event-id",
  relayUrl: "wss://relay.damus.io",
  authorPubkey: "author-pubkey-hex"
)

let ok = await relay.sendReply(seckeyHex, "Reply text", replyTarget)
```

#### プロフィール更新 (kind 0)

```nim
var profile = UserProfile(
  name: "Alice",
  about: "Nim lover",
  picture: "https://example.com/avatar.png"
)
let ok = await relay.sendProfile(seckeyHex, profile)
```

#### プロフィール取得

```nim
await relay.fetchProfile("sub-id", pubkeyHex)
```

#### イベント削除 (kind 5)

```nim
let ok = await relay.deleteEvent(seckeyHex, "event-id-to-delete", "reason (optional)")
```

### サブスクリプション

```nim
var filter = NostrFilter(
  kinds: @[1],
  authors: @["pubkey-hex"],
  limit: 10
)

# 購読開始
await relay.subscribe("my-sub", filter)

# 購読終了
await relay.closeSubscription("my-sub")
```

`NostrFilter` のフィールド:

| フィールド | 型 | 説明 |
|---|---|---|
| `ids` | `seq[string]` | イベント ID でフィルター |
| `authors` | `seq[string]` | 公開鍵でフィルター |
| `kinds` | `seq[int]` | 種類でフィルター |
| `since` | `int64` | このタイムスタンプ以降 |
| `until` | `int64` | このタイムスタンプ以前 |
| `limit` | `int` | 最大件数 |

### データ型

#### NostrEvent

```nim
NostrEvent = object
  id*, pubkey*, content*, sig*: string
  createdAt*: int64
  kind*: int
  tags*: seq[seq[string]]
```

#### NostrKeypair

```nim
NostrKeypair = object
  seckeyHex*, pubkeyHex*: string
  nsec*, npub*: string
```

#### ReplyTarget

```nim
ReplyTarget = object
  eventId*, relayUrl*, authorPubkey*: string
```

#### ThreadContext

```nim
ThreadContext = object
  rootEventId*, replyEventId*: string
  mentionedPubkeys*: seq[string]
```

`parseThreadContext(eventTags: JsonNode)` でイベントのタグからスレッドコンテキストを解析できます。

### Bech32

```nim
let encoded = toBech32("npub", pubkeyHex)
let decoded = fromBech32("npub1...")
# => (hrp: "npub", hex: "abc...")
```

### ユーティリティ

```nim
# イベント ID の計算
let eventId = computeEventId(pubkey, createdAt, kind, tags, content)

# イベント ID への署名
let sig = signEventId(seckeyHex, eventIdHex)

# プロフィール JSON のパース
let profileOpt = parseUserProfile(rawJsonString)
```

## サンプル

`examples/` ディレクトリにサンプルがあります:

| ファイル | 説明 |
|---|---|
| `basic.nim` | 鍵生成、リレー接続、テキストノート送信、イベント購読・受信の基本操作 |
| `reply_bot.nim` | イベントを監視して自動返信するボット |

実行方法:

```bash
nim c -r examples/basic.nim
```

## 依存関係

- `nim >= 2.0.0`
- `ws` — WebSocket クライアント
- `secp256k1` — Schnorr 署名
- `nimSHA2` — SHA-256 ハッシュ

## ライセンス

MIT
