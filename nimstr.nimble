# Package

version       = "0.1.0"
author        = "LunaYoineko"
description   = "Nostr SDK for Nim"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 2.0.0"
requires "ws"
requires "secp256k1"
requires "nimSHA2"
switch("define", "ssl")