import std/[asyncdispatch, json, options, times, random]
import ws
import types, client

proc parseUserProfile*(contentStr: string): Option[UserProfile] =
  try:
    let j = parseJson(contentStr)
    var profile: UserProfile
    profile.rawJson = j
    
    if j.hasKey("name") and j["name"].kind == JString: profile.name = j["name"].getStr()
    if j.hasKey("display_name") and j["display_name"].kind == JString: profile.display_name = j["display_name"].getStr()
    if j.hasKey("about") and j["about"].kind == JString: profile.about = j["about"].getStr()
    if j.hasKey("picture") and j["picture"].kind == JString: profile.picture = j["picture"].getStr()
    if j.hasKey("nip05") and j["nip05"].kind == JString: profile.nip05 = j["nip05"].getStr()
    if j.hasKey("banner") and j["banner"].kind == JString: profile.banner = j["banner"].getStr()
    if j.hasKey("website") and j["website"].kind == JString: profile.website = j["website"].getStr()
    if j.hasKey("lud16") and j["lud16"].kind == JString: profile.lightning_address = j["lud16"].getStr()
      
    return some(profile)
  except CatchableError:
    return none(UserProfile)
    
proc fetchProfile*(relay: RelayClient, subscriptionId: string, pubkeyHex: string) {.async.} =
  let filter = NostrFilter(
    kinds: @[0],
    authors: @[pubkeyHex],
    limit: 1
  )
  await relay.subscribe(subscriptionId, filter)
  
proc sendProfile*(relay: RelayClient, seckeyHex: string, profile: UserProfile): Future[bool] {.async.} =
  if not relay.connected or relay.ws == nil:
    return false

  var profileJson = %*{}
  if profile.name != "": profileJson["name"] = %* profile.name
  if profile.name != "": profileJson["display_name"] = %*profile.display_name
  if profile.about != "": profileJson["about"] = %* profile.about
  if profile.picture != "": profileJson["picture"] = %* profile.picture
  if profile.nip05 != "": profileJson["nip05"] = %* profile.nip05
  if profile.banner != "": profileJson["banner"] = %* profile.banner
  if profile.website != "": profileJson["website"] = %* profile.website
  if profile.lightning_address != "": profileJson["lud16"] = %* profile.lightning_address

  let contentStr = $profileJson
  let kind = 0
  let tags = newJArray()

  return await relay.sendEvent(seckeyHex, kind, tags, contentStr)
  
proc getProfile*(relay: RelayClient, pubkeyHex: string, timeoutMs: int = 3000): Future[Option[UserProfile]] {.async.} =
    if not relay.connected or relay.ws == nil:
        return none(UserProfile)
        
    let subscriptionId = "prof_fetch_" & $int(rand(100000))
    
    try:
        await relay.fetchProfile(subscriptionId, pubkeyHex)
        
        let startTime = epochTime()
        while relay.connected:
            let elapsed = (epochTime() - startTime) * 1000
            if elapsed >= float(timeoutMs):
                break
                
            let msgFut = relay.ws.receiveStrPacket()
            if await withTimeout(msgFut, 200):
                let raw = msgFut.read
                if raw.len > 0 and raw[0] == '[':
                    try:
                        let j = parseJson(raw)
                        if j.kind == JArray and j.len >= 2 and j[0].getStr() == "EVENT":
                            let evJson = if j[1].kind == JObject: j[1] else: (if j.len >= 3 and j[2].kind == JObject: j[2] else: newJNull())
                            if evJson.hasKey("pubkey") and evJson["pubkey"].getStr() == pubkeyHex:
                                if evJson.hasKey("content"):
                                    let profileOpt = parseUserProfile(evJson["content"].getStr())
                                    await relay.closeSubscription(subscriptionId)
                                    return profileOpt
                    except CatchableError:
                        discard
                        
        await relay.closeSubscription(subscriptionId)
        return none(UserProfile)
    except CatchableError:
        try:
            await relay.closeSubscription(subscriptionId)
        except CatchableError:
            discard
        return none(UserProfile)