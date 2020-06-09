import os
import tempfile

when defined(macosx):  # required by tempfile to be friendly with docker
  putEnv "TMP", "/tmp/makeapp"
  "/tmp/makeapp".createDir

var toDelete: seq[string]
var toDelegate: seq[proc()]

var VERBOCITY* = 0
var KEEPONERROR* = false

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
  var (file,name) = mkstemp("f_", mode=if content=="": fmRead else:fmWrite)
  name.deleteLater
  if content != "": file.write content
  file.close
  return name

proc randomDir*():string =
  result = mkdtemp("d_")
  result.deleteLater

proc terminate(message:string, error=true, quiet:bool) =
  if not error or not KEEPONERROR: deleteNow()
  if not quiet: info (if error:"** Error" else:"Success") & (if message!="": ": " & message else:"")
  quit(if error:1 else:0)

proc exit*(quiet=false) = terminate("", error=false, quiet=quiet)

proc kill*(message:string) = terminate(message, quiet=false)

template safedo*(body:untyped) =
  try:
    body
  except:
    writeStackTrace()
    kill getCurrentExceptionMsg()
  