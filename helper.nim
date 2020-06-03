import os, strutils

proc findPlist*(base:string) : string =
  for file in walkDirRec(base):
    if lastPathPart(file) == "Info.plist" and lastPathPart(file.parentDir) == "Contents":
      return file
  return ""

proc findFile(base:string, ext:string): string =
  let ext = "."&ext
  if base.endsWith(ext): return base
  for file in walkDirRec(base):
    if file.endsWith(ext):
      return file
  return ""


proc findDmg*(base:string) : string = findFile(base, "dmg")
proc findZip*(base:string) : string = findFile(base, "zip")

proc findApp*(base:string) : string =
  if base.endsWith(".app"): return base
  if base.endsWith(".app/"): return base.substr(0,base.len-1)
  for file in walkDirRec(base, yieldFilter={pcDir}):
    if file.endsWith(".app"):
      return file
  return ""
