import std/[asyncdispatch, json, times]
import ws
import secp256k1
import types, crypto
    
proc newRelayClient*(url: string): RelayClient =
  result = RelayClient(url: url, ws: nil, connected: false)
  
proc connect*(relay: RelayClient) {.async.} =
  try:
    relay.ws = await newWebSocket(relay.url)
    relay.connected = true
    echo "WebSocket connected successfully."
  except CatchableError as e:
    echo "Failed to connect WebSocket: ", e.msg
    relay.ws = nil
    relay.connected = false
    
proc sendEvent*(relay: RelayClient, seckeyHex: string, kind: int, tags: JsonNode, content: string): Future[bool] {.async.} =
  if not relay.connected or relay.ws == nil:
    return false
      
  let skRes = SkSecretKey.fromHex(seckeyHex)
  if not skRes.isOk: return false
  let sk = skRes.value
  let pubkeyHex = $(sk.toPublicKey().toXOnly())
  let createdAt = getTime().toUnix()
  
  let eventId = computeEventId(pubkeyHex, createdAt, kind, tags, content)
  let sig = signEventId(seckeyHex, eventId)
  if sig == "": return false
  
  let eventMsg = %*[
    "EVENT",
    {
      "id": eventId,
      "pubkey": pubkeyHex,
      "created_at": createdAt,
      "kind": kind,
      "tags": tags,
      "content": content,
      "sig": sig
    }
  ]
  
  try:
    await relay.ws.send($eventMsg)
    return true
  except CatchableError:
    relay.connected = false
    return false

proc sendTextNote*(relay: RelayClient, seckeyHex: string, content: string, extraTags: JsonNode = nil): Future[bool] {.async.} =
  var tags = newJArray()
  if extraTags != nil and extraTags.kind == JArray:
      for t in extraTags:
          tags.add(t)
  return await relay.sendEvent(seckeyHex, 1, tags, content)
    
proc subscription*(relay: RelayClient, subscriptionId: string, filter: NostrFilter) {.async.} =
  if not relay.connected or relay.ws == nil: return
  
  var fObj = %*{}
  if filter.ids.len > 0: fObj["ids"] = %* filter.ids
  if filter.authors.len > 0: fObj["authors"] = %* filter.authors
  if filter.kinds.len > 0: fObj["kinds"] = %* filter.kinds
  if filter.since > 0: fObj["since"] = %* filter.since
  if filter.until > 0: fObj["until"] = %* filter.until
  if filter.limit > 0: fObj["limit"] = %* filter.limit
  
  let reqMsg = %*["REQ", subscriptionId, fObj]
  try:
    await relay.ws.send($reqMsg)
  except CatchableError:
    relay.connected = false
    
proc closeSubscription*(relay: RelayClient, subscriptionId: string) {.async.} =
  if not relay.connected or relay.ws == nil: return
  let closeMsg = %*["CLOSE", subscriptionId]
  try:
    await relay.ws.send($closeMsg)
  except CatchableError:
    relay.connected = false    

proc close*(relay: RelayClient) {.async.} =
  if relay.ws != nil:
    try:
      relay.ws.close()
    except CatchableError:
      discard
    relay.connected = false