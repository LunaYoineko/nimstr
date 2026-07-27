import std/[strutils, sequtils, algorithm]

const CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

proc polymod(values: openArray[int]): int =
    var chk = 1
    let generators = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
    for v in values:
        let top = chk shr 25
        chk = ((chk and 0x1ffffff) shl 5) xor v
        for i in 0..<5:
            if ((top shr i) and 1) != 0:
                chk = chk xor generators[i]
    return chk xor 1
    
proc expandHrp(hrp: string): seq[int] =
    var ret = newSeq[int]()
    for c in hrp:
        ret.add(ord(c) shr 5)
    ret.add(0)
    for c in hrp:
        ret.add(ord(c) and 31)
    return ret
    
proc convertBits(data: openArray[int], fromBits, toBits: int, pad: bool): seq[int] =
    var
        acc = 0
        bits = 0
    let
        maxVal = (1 shl toBits) - 1
        maxAcc = (1 shl (fromBits + toBits - 1)) - 1
        
    result = @[]
    for val in data:
        if val < 0 or (val shr fromBits) != 0:
            return @[]
        acc = ((acc shl fromBits) or val) and maxAcc
        bits += fromBits
        while bits >= toBits:
            bits -= toBits
            result.add((acc shr bits) and maxVal)
            
    if pad:
        if bits > 0:
            result.add((acc shl (toBits - bits)) and maxVal)
    elif bits >= fromBits or ((acc shl (toBits - bits)) and maxVal) != 0:
        return @[]
        
proc bech32Encode(hrp: string, data: openArray[int]): string =
    let combined = expandHrp(hrp) & @data
    let check = polymod(combined)
    var checksum = newSeq[int](6)
    for i in 0..<6:
        checksum[i] = (check shr (5 * (5 - i))) and 31
        
    let total = @data & checksum
    result = hrp & "1"
    for d in total:
        result.add(CHARSET[d])
        
proc hexToBytes(hex: string): seq[int] =
    result = @[]
    var i = 0
    while i < hex.len:
        let byteStr = hex[i..i+1]
        result.add(parseHexInt(byteStr))
        i += 2
        
proc bytesToHex(bytes: openArray[int]): string =
    result = ""
    for b in bytes:
        result.add(toHex(b, 2).toLowerAscii())
        
proc toBech32*(hrp: string, hexStr: string): string =
    let dataBytes = hexToBytes(hexStr)
    let converted = convertBits(dataBytes, 8, 5, true)
    return bech32Encode(hrp, converted)
    
proc fromBech32*(bechStr: string): tuple[hrp: string, hex: string] =
    let lower = bechStr.toLowerAscii()
    let pos = lower.rfind('1')
    if pos == -1 or pos < 1 or pos + 7 > lower.len:
        raise newException(ValueError, "Invalid Bech32 string format")
    
    let hrp = lower[0..<pos]
    var data = newSeq[int]()
    for i in pos + 1..<lower.len:
        let idx = CHARSET.find(lower[i])
        if idx == -1:
            raise newException(ValueError, "Invalid character in Bech32 string")
        data.add(idx)
        
    let decoded = convertBits(data[0..^7], 5, 8, false)
    if decoded.len == 0:
        raise newException(ValueError, "Failed to convert bits for Bech32")
        
    return (hrp: hrp, hex: bytesToHex(decoded))