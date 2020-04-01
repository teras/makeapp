import os, strutils

proc findPlist*(base:string) : string =
    for file in walkDirRec(base):
        if lastPathPart(file) == "Info.plist" and lastPathPart(file.parentDir) == "Contents":
            return file
    echo "Unable to locate PList"
    return ""

proc findDmg*(base:string) : string =
    for file in walkDirRec(base):
        if file.endsWith(".dmg"):
            return file
    echo "Unable to locate DMG"
    return ""

proc findApp*(base:string) : string =
    for file in walkDirRec(base, yieldFilter={pcDir}):
        if file.endsWith(".app"):
            return file
    echo "Unable to locate App"
    return ""
