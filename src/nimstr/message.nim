import std/[asyncdispatch, json]
import types, client

proc sendTextNote*(
    relay: RelayClient,
    seckeyHex: string,
    content: string,
    extraTags: JsonNode = nil
): Future[bool] {.async.} =
  var tags = newJArray()
  if extraTags != nil and extraTags.kind == JArray:
      for t in extraTags:
          tags.add(t)
  return await relay.sendEvent(seckeyHex, 1, tags, content)

proc sendTextNoteAll*(pool: RelayPool, seckeyHex: string, content: string, extraTags: JsonNode = nil): Future[int] {.async.} =
  var tags = newJArray()
  if extraTags != nil and extraTags.kind == JArray:
      for t in extraTags:
          tags.add(t)
  return await pool.sendEventAll(seckeyHex, 1, tags, content)
  
proc sendReply*(
  relay: RelayClient, 
  seckeyHex: string, 
  content: string, 
  replyTo: ReplyTarget, 
  extraTags: JsonNode = nil
): Future[bool] {.async.} =
  if not relay.connected or relay.ws == nil:
    return false

  var tags = newJArray()

  var replyTag = %*[ "e", replyTo.eventId, replyTo.relayUrl, "reply" ]
  tags.add(replyTag)

  if replyTo.authorPubkey != "":
    tags.add(%*[ "p", replyTo.authorPubkey ])

  if extraTags != nil and extraTags.kind == JArray:
    for t in extraTags:
      tags.add(t)

  return await relay.sendEvent(seckeyHex, 1, tags, content)

proc sendRootReply*(
    relay: RelayClient,
    seckeyHex: string,
    content: string,
    replyTo: ReplyTarget,
    extraTags: JsonNode = nil
): Future[bool] {.async.} =
    if not relay.connected or relay.ws == nil:
        return false
        
    var tags = newJArray()
    
    var replyTag = %*[ "e", replyTo.eventId, replyTo.relayUrl, "root" ]
    tags.add(replyTag)
    
    if replyTo.authorPubkey != "":
        tags.add(%*[ "p", replyTo.authorPubkey ])
        
    if extraTags != nil and extraTags.kind == JArray:
        for t in extraTags:
            tags.add(t)
            
    return await relay.sendEvent(seckeyHex, 1, tags, content)
  
proc sendReplyAll*(
    pool: RelayPool,
    seckeyHex: string,
    content: string,
    replyTo: ReplyTarget,
    extraTags: JsonNode = nil
): Future[int] {.async.} =
  var tags = newJArray()
  
  var replyTag = %*[ "e", replyTo.eventId, replyTo.relayUrl, "reply" ]
  tags.add(replyTag)
  
  if replyTo.authorPubkey != "":
      tags.add(%*[ "p", replyTo.authorPubkey ])
      
  if extraTags != nil and extraTags.kind == JArray:
      for t in extraTags:
          tags.add(t)
          
  var successCount = 0
  for r in pool.relays:
      if r.connected:
          let ok = await r.sendEvent(seckeyHex, 1, tags, content)
          if ok:
              successCount += 1
  return successCount

proc sendRootReplyAll*(
    pool: RelayPool,
    seckeyHex: string,
    content: string,
    replyTo: ReplyTarget,
    extraTags: JsonNode = nil
): Future[int] {.async.} =
    var tags = newJArray()
    
    var replyTag = %*[ "e", replyTo.eventId, replyTo.relayUrl, "root" ]
    tags.add(replyTag)
    
    if replyTo.authorPubkey != "":
        tags.add(%*[ "p", replyTo.authorPubkey ])
        
    if extraTags != nil and extraTags.kind == JArray:
        for t in extraTags:
            tags.add(t)
            
    var successCount = 0
    for r in pool.relays:
        if r.connected:
            let ok = await r.sendEvent(seckeyHex, 1, tags, content)
            if ok:
                successCount += 1
    return successCount
  
proc parseThreadContext*(eventTags: JsonNode): ThreadContext =
  var ctx = ThreadContext(rootEventId: "", replyEventId: "", mentionedPubkeys: @[])
  
  if eventTags.kind != JArray:
    return ctx

  var eTags: seq[tuple[id: string, marker: string]] = @[]

  for tag in eventTags:
    if tag.kind == JArray and tag.len >= 2:
      let tagName = tag[0].getStr()
      if tagName == "e":
        let eventId = tag[1].getStr()
        var marker = ""
        if tag.len >= 4:
          marker = tag[3].getStr()
        eTags.add((id: eventId, marker: marker))
      elif tagName == "p":
        ctx.mentionedPubkeys.add(tag[1].getStr())

  for t in eTags:
    if t.marker == "root":
      ctx.rootEventId = t.id
    elif t.marker == "reply":
      ctx.replyEventId = t.id

  if ctx.rootEventId == "" and ctx.replyEventId == "" and eTags.len > 0:
    if eTags.len == 1:
      ctx.replyEventId = eTags[0].id
    else:
      ctx.rootEventId = eTags[0].id
      ctx.replyEventId = eTags[^1].id

  return ctx