import os, tempfile

var toDelete: seq[string]
var toDelegate: seq[proc()]

var VERBOCITY*: int = 0

proc info*(message:string) = echo message

proc deleteLater*(file:string) = toDelete.add file
proc delegateLater*(procedure:proc()) = toDelegate.add procedure

proc deleteNow() =
  for f in toDelete:
    if f.fileExists:
      f.removeFile
    elif f.dirExists:
      f.removeDir
  for f in toDelegate:
    try: f()
    except: discard

proc randomFile*(content=""): string =
  var (file,name) = mkstemp("makeapp_f_", mode=if content=="": fmRead else:fmWrite)
  name.deleteLater
  if content != "": file.write content
  file.close
  return name

proc randomDir*():string =
  result = mkdtemp("makeapp_d_")
  result.deleteLater

proc terminate(message:string, error=true, quiet:bool) =
  deleteNow()
  if not quiet:
    info (if error:"** Error" else:"Success") & (if message!="": ": " & message else:"")
  quit(if error:1 else:0)

proc exit*(quiet=false) = terminate("", error=false, quiet=quiet)

proc kill*(message:string) = terminate(message, quiet=false)

template safedo*(body:untyped) =
  try:
    body
  except:
    writeStackTrace()
    kill getCurrentExceptionMsg()
  