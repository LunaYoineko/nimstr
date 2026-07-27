import ws

type
  NostrEvent* = object
    id*: string
    pubkey*: string
    createdAt*: int64
    kind*: int
    tags*: seq[seq[string]]
    content*: string
    sig*: string
    
  NostrFilter* = object
    ids*: seq[string]
    authors*: seq[string]
    kinds*: seq[int]
    since*: int64
    until*: int64
    limit*: int
    
  NostrKeypair* = object
    seckeyHex*: string
    pubkeyHex*: string
    nsec*: string
    npub*: string
    
  RelayClient* = ref object
    url*: string
    ws*: WebSocket
    connected*: bool