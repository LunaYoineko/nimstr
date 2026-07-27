import std/[asyncdispatch, json]
import types, client

proc newRelayClient*(url: string): RelayClient =
  result = RelayClient(url: url, ws: nil, connected: false)
  
proc newRelayPool*(urls: seq[string]): RelayPool =
  var clients: seq[RelayClient] = @[]
  for url in urls:
      clients.add(newRelayClient(url))
  result = RelayPool(relays: clients)

proc connect*(relay: RelayClient) {.async.} =
  try:
    relay.ws = await newWebSocket(relay.url)
    relay.connected = true
    echo "WebSocket connected successfully."
  except CatchableError as e:
    echo "Failed to connect WebSocket: ", e.msg
    relay.ws = nil
    relay.connected = false
  
proc connectAll*(pool: RelayPool) {.async.} =
  var futures: seq[Future[void]] = @[]
  for r in pool.relays:
      futures.add(r.connect())
  for f in futures:
      await f

proc close*(relay: RelayClient) {.async.} =
  if relay.ws != nil:
    try:
      relay.ws.close()
    except CatchableError:
      discard
    relay.connected = false
      
proc closeAll*(pool: RelayPool) {.async.} =
  for r in pool.relays:
      r.close()