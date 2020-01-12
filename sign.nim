import osproc, os

{.compile: "fileloader.c".}
proc needsSigning(path:cstring):bool {.importc.}

proc signFile(path:string, key:string) :bool =
    if execCmd("codesign --deep --force --verify --verbose --options runtime --sign " & key.quoteShell & " " & path.quoteShell) != 0:
        return false
    if execCmd("codesign --verify --verbose " & path.quoteShell) != 0:
        return false
    return true

proc sign*(path:string, id:string) =
    for file in walkDirRec(path):
        if file.cstring.needsSigning:
            if not signFile(file, id):
                quit("Unable to sign file " & file)
    if not signFile(path, id):
        echo "Unable to sign Application " & path
    echo " *** Sign successful"