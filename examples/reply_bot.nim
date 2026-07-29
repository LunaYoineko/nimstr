import std/[asyncdispatch, json, strutils]
import nimstr

proc replyToMentions(botKeypair: NostrKeypair) {.async.} =
  let relay = newRelayClient("wss://relay.damus.io")
  await relay.connect()
  if not relay.connected:
    echo "Failed to connect"
    return

  echo "Bot listening as: ", botKeypair.npub

  # 自分の公開鍵宛てのメンションを購読
  var filter = NostrFilter(
    kinds: @[1],
    limit: 0
  )
  await relay.subscribe("bot", filter)

  while true:
    let msg = await relay.ws.receiveStrPacket()
    let json = parseJson(msg)

    if json[0].getStr() != "EVENT":
      continue

    let event = json[2]
    let content = event["content"].getStr()
    let pubkey = event["pubkey"].getStr()
    let eventId = event["id"].getStr()

    # 自分からのイベントは無視
    if pubkey == botKeypair.pubkeyHex:
      continue

    echo "Received: ", content

    let target = ReplyTarget(
      eventId: eventId,
      relayUrl: "wss://relay.damus.io",
      authorPubkey: pubkey
    )

    let reply = "Echo: " & content
    let ok = await relay.sendReply(botKeypair.seckeyHex, reply, target)
    echo "Replied: ", ok

proc main() {.async.} =
  let bot = keypairFromSecret("nsec1...")
  await replyToMentions(bot)

waitFor main()
