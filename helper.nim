import os, strutils, autos, types, parsecfg, myexec

proc icon*(res:Resource, name:string, ostype:OSType):string =
  let ext = case ostype:
    of pMacos: "icns"
    of pWin32, pWin64: "ico"
    else: "png"
  let given = res.path(name & "." & ext)
  if given.fileExists: return given

  let png = res.path(name & ".png")
  if png=="": return ""
  if windowsTargets.contains(ostype):
    podmanUser "", "-v", res.base&":/data/base", "-v", res.gen&":/data/gen", "teras/appimage-builder", 
      "convert", "/data/base/"&name&".png", "/data/gen/"&name&".ico"
    return res.gen/name&".ico"
  elif ostype == pMacos:
    podmanUser "", "-v", res.base&":/data/base", "-v", res.gen&":/data/gen", "teras/appimage-builder", 
      "png2icns", "/data/gen/"&name&".icns", "/data/base/"&name&".png"
    return res.gen/name&".icns"
  return ""

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

proc findSubstring*(list:seq[string], what:string):string =
  for s in list:
    if what in s: return s
  return ""

proc findDmg*(base:string) : string = findFile(base, "dmg")
proc findZip*(base:string) : string = findFile(base, "zip")

proc findApp*(ostype:OSType, base:string) : string =
  let ext = "." & ostype.appx
  if base.endsWith(ext): return base
  if base.endsWith(ext & "/"): return base.substr(0,base.len-1)
  for file in walkDirRec(base, yieldFilter={pcDir}):
    if file.endsWith(ext):
      return file
  return ""

proc isTrue*(val:string): bool =
  let val = val.strip.toLowerAscii
  return val == "1" or val.startsWith("t") or val.startsWith("y") or val.startsWith("e")

proc checkParam*(param:string, error:string, asFile=false, asDir=false): string {.discardable.}=
  let param=param.strip
  if param == "": kill error
  if asFile and not param.fileExists: kill "Unable to locate file " & param.absolutePath
  if asDir and not param.dirExists: kill "Unable to locate directory " & param.absolutePath
  return param

proc contains*[T](a: openArray[T], items: openArray[T]): bool =
  for item in items:
    if a.contains(item):
      return true
  return false

proc checkPass*(config:Config, value,tag,error:string, os:seq[OSType], possibleOS:seq[OSType], noSignOS:seq[OSType]):string =
  result = if value != "" : value else: getEnv(tag, config.getSectionValue("", tag))
  if result == "":
    for current in os:
      if possibleOS.contains(current) and not noSignOS.contains(current): kill error

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

proc safe*(name:string):string {.inline.}= name.replace(' ','_')

proc readContent*(file, descr:string):string =
  if file == "": kill "No " & descr & " file provided"
  elif not file.fileExists: kill "No " & descr & " file exists under " & file
  let lines = file.readLines(1)
  if lines.len != 1: kill "More than one line found in " & descr & " file " & file
  result = lines[0].strip
  if result.len == 0: kill "THe data of " & descr & " file " & file & " is empty"

template makeExec*(file:string) = file.inclFilePermissions({FilePermission.fpUserExec, FilePermission.fpGroupExec})
