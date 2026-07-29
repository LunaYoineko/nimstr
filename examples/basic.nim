import std/[asyncdispatch, json]
import nimstr

proc main() {.async.} =
  # 1. 鍵を生成
  let alice = generateKeypair()
  echo "Alice npub: ", alice.npub
  echo "Alice nsec: ", alice.nsec

  # 2. 既存の秘密鍵から復元
  let restored = keypairFromSecret(alice.nsec)
  assert restored.pubkeyHex == alice.pubkeyHex
  echo "Restored: ", restored.npub

  # 3. リレーに接続
  let relay = newRelayClient("wss://relay.damus.io")
  await relay.connect()
  if not relay.connected:
    echo "Failed to connect"
    return

  # 4. テキストノートを送信
  echo "\n--- Sending text note ---"
  let ok = await relay.sendTextNote(alice.seckeyHex, "Hello from Nimstr!")
  echo "Sent: ", ok

  # 5. イベントを購読
  echo "\n--- Subscribing to events ---"
  var filter = NostrFilter(
    kinds: @[1],
    limit: 3
  )
  await relay.subscribe("test", filter)

  # 6. 受信ループ
  for i in 0..<10:
    let msg = await relay.ws.receiveStrPacket()
    let json = parseJson(msg)
    if json[0].getStr() == "EVENT":
      let event = json[2]
      echo "Received: ", event["content"].getStr()
    elif json[0].getStr() == "EOSE":
      echo "End of stored events"
      break

  await relay.closeSubscription("test")
  await relay.close()

waitFor main()
