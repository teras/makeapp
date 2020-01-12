import os, strutils

proc findPlist*() : string =
    for file in walkDirRec(getCurrentDir()):
        if lastPathPart(file) == "Info.plist" and lastPathPart(file.parentDir) == "Contents":
            return file
    echo "Unable to locate PList"
    return ""

proc findDmg*() : string =
    for file in walkDirRec(getCurrentDir()):
        if file.endsWith(".dmg"):
            return file
    echo "Unable to locate DMG"
    return ""

proc findApp*() : string =
    for file in walkDirRec(getCurrentDir(), yieldFilter={pcDir}):
        if file.endsWith(".app"):
            return file
    echo "Unable to locate App"
    return ""
