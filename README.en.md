# Nimstr

A Nostr SDK for Nim. Supports key generation, event signing and publishing, relay connections, and Bech32 encoding.

## Features

- **Key management** — Generate keypairs, restore from nsec/hex
- **Event signing** — Schnorr signatures (secp256k1) for Nostr events
- **Relay connections** — WebSocket-based relay communication
- **Event publishing** — Text notes (kind 1), replies, profile updates (kind 0), deletion (kind 5)
- **Subscriptions** — Filter-based event subscription (REQ/CLOSE)
- **Bech32** — Encode/decode nsec, npub
- **Relay pool** — Connect to multiple relays and broadcast simultaneously

## Installation

```bash
# 1. Create a project
mkdir myapp && cd myapp
nimble init

# 2. Install nimstr
nimble install https://github.com/LunaYoineko/nimstr

# 3. Add dependency to your .nimble file
# Add the following to the dependencies section of myapp.nimble:
#   requires "nimstr"

# 5. Compile and run
nim c -r src/myapp.nim
```

**Note**: Transitive dependencies (ws, secp256k1, nimSHA2) are resolved automatically with `requires "nimstr"`. If SSL is needed, add `switch("define", "ssl")` to your project's `config.nims`.

## Quick Start

```nim
import std/asyncdispatch
import nimstr

proc main() {.async.} =
  # Generate keys
  let keypair = generateKeypair()
  echo "npub: ", keypair.npub
  echo "nsec: ", keypair.nsec

  # Connect to a relay
  let relay = newRelayClient("wss://relay.damus.io")
  await relay.connect()

  # Send a text note
  let ok = await relay.sendTextNote(keypair.seckeyHex, "Hello, Nostr!")
  echo "Sent: ", ok

  # Close
  await relay.close()

waitFor main()
```

## API

### Key Generation & Recovery

| Function | Description |
|---|---|
| `generateKeypair()` | Generate a new keypair. Returns `NostrKeypair` (seckeyHex, pubkeyHex, nsec, npub) |
| `keypairFromSecret(secretInput: string)` | Restore a keypair from hex secret key or nsec |

```nim
let kp = generateKeypair()
echo kp.npub  # npub1...

let restored = keypairFromSecret(kp.nsec)
assert restored.pubkeyHex == kp.pubkeyHex
```

### Relay Connection

| Function | Description |
|---|---|
| `newRelayClient(url: string)` | Create a single relay client |
| `newRelayPool(urls: seq[string])` | Create a pool of relay clients |
| `connect(relay)` | Connect to a relay via WebSocket |
| `connectAll(pool)` | Connect to all relays in the pool |
| `close(relay)` / `closeAll(pool)` | Disconnect |

```nim
# Single relay
let relay = newRelayClient("wss://relay.damus.io")
await relay.connect()

# Relay pool
let pool = newRelayPool(@[
  "wss://relay.damus.io",
  "wss://nos.lol"
])
await pool.connectAll()
```

### Events

#### Text Note (kind 1)

```nim
# Send to a single relay
let ok = await relay.sendTextNote(seckeyHex, "Hello, Nostr!")

# Broadcast to all relays
let count = await pool.sendTextNoteAll(seckeyHex, "Hello, Nostr!")
```

#### Reply (kind 1 + tags)

```nim
let replyTarget = ReplyTarget(
  eventId: "previous-event-id",
  relayUrl: "wss://relay.damus.io",
  authorPubkey: "author-pubkey-hex"
)

let ok = await relay.sendReply(seckeyHex, "Reply text", replyTarget)
```

#### Profile Update (kind 0)

```nim
var profile = UserProfile(
  name: "Alice",
  about: "Nim lover",
  picture: "https://example.com/avatar.png"
)
let ok = await relay.sendProfile(seckeyHex, profile)
```

#### Fetch Profile

```nim
await relay.fetchProfile("sub-id", pubkeyHex)
```

#### Delete Event (kind 5)

```nim
let ok = await relay.deleteEvent(seckeyHex, "event-id-to-delete", "reason (optional)")
```

### Subscriptions

```nim
var filter = NostrFilter(
  kinds: @[1],
  authors: @["pubkey-hex"],
  limit: 10
)

# Start subscription
await relay.subscribe("my-sub", filter)

# Close subscription
await relay.closeSubscription("my-sub")
```

`NostrFilter` fields:

| Field | Type | Description |
|---|---|---|
| `ids` | `seq[string]` | Filter by event IDs |
| `authors` | `seq[string]` | Filter by pubkeys |
| `kinds` | `seq[int]` | Filter by event kinds |
| `since` | `int64` | Events after this timestamp |
| `until` | `int64` | Events before this timestamp |
| `limit` | `int` | Maximum number of events |

### Data Types

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

Use `parseThreadContext(eventTags: JsonNode)` to parse thread context from event tags.

### Bech32

```nim
let encoded = toBech32("npub", pubkeyHex)
let decoded = fromBech32("npub1...")
# => (hrp: "npub", hex: "abc...")
```

### Utilities

```nim
# Compute event ID
let eventId = computeEventId(pubkey, createdAt, kind, tags, content)

# Sign an event ID
let sig = signEventId(seckeyHex, eventIdHex)

# Parse profile JSON
let profileOpt = parseUserProfile(rawJsonString)
```

## Examples

The `examples/` directory contains sample programs:

| File | Description |
|---|---|
| `basic.nim` | Key generation, relay connection, sending text notes, subscribing and receiving events |
| `reply_bot.nim` | Event monitoring bot that auto-replies |

Run an example:

```bash
nim c -r examples/basic.nim
```

## Dependencies

- `nim >= 2.0.0`
- `ws` — WebSocket client
- `secp256k1` — Schnorr signatures
- `nimSHA2` — SHA-256 hashing

## License

MIT
