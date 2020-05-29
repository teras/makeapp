import osproc, os, strutils, nim_miniz, sets, tempfile

{.compile: "fileloader.c".}
proc needsSigning(path:cstring):bool {.importc.}

proc signFile(path:string, id:string, entitlements:string) :bool =
    let entitlementsCmd = if entitlements == "": "" else: " --entitlements " & entitlements.quoteShell
    if execCmd("codesign --timestamp --deep --force --verify --verbose --options runtime --sign " & id.quoteShell & entitlementsCmd & " " & path.quoteShell) != 0:
        return false
    if execCmd("codesign --verify --verbose " & path.quoteShell) != 0:
        return false
    return true

proc endsWith(filename:string, otherExts:HashSet[string]) :bool =
    for ending in otherExts:
        if filename.endsWith(ending):
            return true
    return false

proc signZippedEntries(zipfile:string, id:string, entitlements:string, otherExts:HashSet[string]) =
    var tempdir = ""
    # Extract and sign files
    var zip:Zip
    if not zip.open(zipfile):
        quit("Unable to open compressed file " & zipfile)
    for i,fname in zip:
        if fname.endsWith(".jnilib") or fname.endsWith(".dylib") or fname.endsWith(otherExts):
            if tempdir=="": tempdir = mkdtemp("notsign_")
            discard zip.extract_file(fname, tempdir)
            if not signFile(tempdir / fname, id, entitlements):
                quit("Unable to sign file " & fname)
    zip.close()
    # Replace extracted files
    if tempdir != "":
        for file in walkDirRec(tempdir, relative=true):
            if execCmd("jar -uf " & zipfile.quoteShell & " -C " & tempdir.quoteShell & " " & file)!=0:
                quit("Errors while updating JAR")
            else: echo zipfile & "!" & file & ": signed"
        tempdir.removeDir

proc sign*(path:string, id:string, entitlements:string, otherExts:HashSet[string]) =
    echo "Signing: " & path
    for file in walkDirRec(path):
        if file.endsWith(".jnilib") or file.endsWith(".dylib") or file.endsWith(otherExts) or file.cstring.needsSigning:
            if not signFile(file, id, entitlements):
                quit("Unable to sign file " & file)
        if file.endsWith(".jar"):
            signZippedEntries(file, id, entitlements, otherExts)
    if not signFile(path, id, entitlements):
        quit("Unable to sign Application " & path)
    echo " *** Sign successful"
