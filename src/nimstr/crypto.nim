import std/[strutils, json, random]
import secp256k1
import nimSHA2
import types, bech32
    
proc generateKeypair*(): NostrKeypair =
  var seckeyBytes: array[32, byte]
  let rng: secp256k1.Rng = proc(data: var openArray[byte]): bool =
    for i in 0..<data.len:
      data[i] = byte(rand(255))
    true
    
  while true:
    var hex = ""
    for i in 0..<32:
      hex.add(toHex(rand(255), 2))
    hex = hex.toLowerAscii()
    
    let skRes = SkSecretKey.fromHex(hex)
    if skRes.isOk:
      let sk = skRes.value
      let pk = sk.toPublicKey()
      let xonly = pk.toXOnly()
      let seckeyHex = ($sk).toLowerAscii()
      let pubkeyHex = ($xonly).toLowerAscii()
      return NostrKeypair(
        seckeyHex: seckeyHex,
        pubkeyHex: pubkeyHex,
        nsec: toBech32("nsec", seckeyHex),
        npub: toBech32("npub", pubkeyHex)
      )

proc keypairFromSecret*(secretInput: string): NostrKeypair =
  var seckeyHex = secretInput
  if secretInput.startsWith("nsec1"):
    let decoded = fromBech32(secretInput)
    seckeyHex = decoded.hex
    
  let skRes = SkSecretKey.fromHex(seckeyHex)
  if not skRes.isOk:
    raise newException(ValueError, "Invalid secret key format")
    
  let sk = skRes.value
  let pubkeyHex = $(sk.toPublicKey().toXOnly())
  
  result.seckeyHex = seckeyHex
  result.pubkeyHex = pubkeyHex
  result.nsec = toBech32("nsec", seckeyHex)
  result.npub = toBech32("npub", pubkeyHex)
      
proc computeEventId*(pubkey: string, createdAt: int64, kind: int, tags: JsonNode, content: string): string =
  let serializeArray = %*[0, pubkey, createdAt, kind, tags, content]
  let hashData = computeSHA256($serializeArray)
  let hashStr = hashData.hex.toLowerAscii()
  result = ""
  for i in 0 ..< 32:
    result.add(hashStr[i*2..i*2+1])
    
proc signEventId*(seckeyHex: string, eventIdHex: string): string =
  let skRes = SkSecretKey.fromHex(seckeyHex)
  if not skRes.isOk: return ""
  let seckey = skRes.value
  
  var hashBytes: array[32, byte]
  for i in 0 ..< 32:
    hashBytes[i] = parseHexInt(eventIdHex[i*2..i*2+1]).byte
      
  let msgRes = SkMessage.fromBytes(hashBytes)
  if not msgRes.isOk: return ""
  let msg = msgRes.value
  
  let rng: secp256k1.Rng = proc(data: var openArray[byte]): bool =
    for i in 0..<data.len:
      data[i] = byte(rand(255))
    true
    
  let sigRes = seckey.signSchnorr(msg, rng)
  if not sigRes.isOk: return ""
  result = ($sigRes.value).toLowerAscii()