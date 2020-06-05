import os, strutils, posix, autos

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

proc findUsername*(): string =
  let userC = getlogin()
  let len = userC.high+1
  result = newString(len)
  copyMem(addr(result[0]), userC, len)

proc isTrue*(val:string): bool =
  let val = val.strip.toLowerAscii
  return val == "1" or val.startsWith("t") or val.startsWith("y")

proc checkParam*(param:string, error:string, asFile=false, asDir=false): string {.discardable.}=
  let param=param.strip
  if param == "": kill error
  if asFile and not param.fileExists: kill "Unable to locate file " & param.absolutePath
  if asDir and not param.dirExists: kill "Unable to locate directory " & param.absolutePath
  return param

proc merge*(basedir:string, otherdir:string) =
  basedir.createDir
  for file in otherdir.walkDirRec(relative=true, yieldFilter={pcFile, pcDir}):
    let src = otherdir / file
    let dest = basedir / file
    if src.dirExists:
      dest.createDir
    elif src.fileExists:
      copyFileWithPermissions src, dest
    else:
      kill("Unknown file at " & src)