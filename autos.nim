import os

var toDelete: seq[string]
var toDelegate: seq[proc()]

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

proc terminate(message:string, error=true) =
    deleteNow()
    echo (if error:"** Error" else:"Success") & (if message!="": ": " & message else:"")
    quit(if error:1 else:0)

proc exit*() = terminate("", error=false)

proc kill*(message:string) = terminate(message)