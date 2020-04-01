import os, strutils

proc findPlist*(base:string) : string =
    for file in walkDirRec(base):
        if lastPathPart(file) == "Info.plist" and lastPathPart(file.parentDir) == "Contents":
            return file
    return ""

proc findDmg*(base:string) : string =
    if base.endsWith(".dmg"): return base
    for file in walkDirRec(base):
        if file.endsWith(".dmg"):
            return file
    return ""

proc findApp*(base:string) : string =
    if base.endsWith(".app"): return base
    for file in walkDirRec(base, yieldFilter={pcDir}):
        if file.endsWith(".app"):
            return file
    return ""
