import os

var toDelete: seq[string]

proc deleteLater*(file:string) = toDelete.add file

proc deleteNow() =
    for f in toDelete:
        if f.fileExists:
            f.removeFile
        elif f.dirExists:
            f.removeDir

proc terminate(message:string, error=true) =
    deleteNow()
    echo (if error:"** Error" else:"Success") & (if message!="": ": " & message else:"")
    quit(if error:1 else:0)

proc exit*() = terminate("", error=false)

proc kill*(message:string) = terminate(message)