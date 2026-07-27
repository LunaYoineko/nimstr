import std/[asyncdispatch, json, times]
import ws
import secp256k1
import types, crypto
    
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

proc sendEventAll*(pool: RelayPool, seckeyHex: string, kind: int, tags: JsonNode, content: string): Future[int] {.async.} =
  var successCount = 0
  for r in pool.relays:
      if r.connected:
          let ok = await r.sendEvent(seckeyHex, kind, tags, content)
          if ok:
              successCount += 1
  return successCount
    
proc deleteEvent*(
    relay: RelayClient,
    seckeyHex: string,
    eventIdHex: string,
    reason: string = ""
): Future[bool] {.async.} =
  if not relay.connected or relay.ws == nil:
      return false
      
  var tags = newJArray()
  tags.add(%*[ "e", eventIdHex ])
  
  let content = reason
  
  return await relay.sendEvent(seckeyHex, 5, tags, content)
    
proc deleteEventAll*(
    pool: RelayPool,
    seckeyHex: string,
    eventIdHex: string,
    reason: string = ""
): Future[int] {.async.} =
  var successCount = 0
  for r in pool.relays:
      if r.connected:
          let ok = await r.deleteEvent(seckeyHex, eventIdHex, reason)
          if ok:
              successCount += 1
  return successCount
  
proc subscribe*(relay: RelayClient, subscriptionId: string, filter: NostrFilter) {.async.} =
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

proc subscribeAll*(pool: RelayPool, subscriptionId: string, filter: NostrFilter) {.async.} =
  for r in pool.relays:
      if r.connected:
          await r.subscribe(subscriptionId, filter)
    
proc closeSubscription*(relay: RelayClient, subscriptionId: string) {.async.} =
  if not relay.connected or relay.ws == nil: return
  let closeMsg = %*["CLOSE", subscriptionId]
  try:
    await relay.ws.send($closeMsg)
  except CatchableError:
    relay.connected = false
    
proc closeSubscriptionAll*(pool: RelayPool, subscriptionId: string) {.async.} =
  for r in pool.relays:
      if r.connected:
          await r.closeSubscription(subscriptionId)

