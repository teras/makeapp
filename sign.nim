import osproc, os, strutils, nim_miniz, sets, tempfile, myexec

{.compile: "fileloader.c".}
proc needsSigning(path:cstring):bool {.importc.}

const DEFAULT_ENTITLEMENT = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-executable-page-protection</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <true/>
</dict>
</plist>
"""

proc getDefaultEntitlementFile*(): string =
    let (file,name) = mkstemp(prefix="notr_ent_", mode=fmWrite)
    file.write(DEFAULT_ENTITLEMENT)
    file.close
    use_temp_entitlements = true
    return name

proc signFile(path:string) =
    myexec "Sign " & (if path.existsDir: "app" else: "file") & " " & path.extractFilename, "codesign --timestamp --deep --force --verify --verbose --options runtime --sign " & ID.quoteShell &
        " --entitlements " & ENTITLEMENTS.quoteShell & " " & path.quoteShell
    myexec "", "codesign --verify --verbose " & path.quoteShell

proc endsWith(filename:string, otherExts:HashSet[string]) :bool =
    for ending in otherExts:
        if filename.endsWith(ending):
            return true
    return false

proc signZippedEntries(zipfile:string, otherExts:HashSet[string]) =
    var tempdir = ""
    # Extract and sign files
    var zip:Zip
    if not zip.open(zipfile): kill "Unable to open compressed file " & zipfile
    for i,fname in zip:
        if fname.endsWith(".jnilib") or fname.endsWith(".dylib") or fname.endsWith(otherExts):
            if tempdir=="": tempdir = mkdtemp("notsign_")
            discard zip.extract_file(fname, tempdir)
            signFile(tempdir / fname)
    zip.close()
    # Replace extracted files
    if tempdir != "":
        for file in walkDirRec(tempdir, relative=true):
            myexec "", "jar -uf " & zipfile.quoteShell & " -C " & tempdir.quoteShell & " " & file
            echo zipfile & "!" & file & ": signed"
        tempdir.removeDir

proc sign*(path:string, otherExts:HashSet[string]) =
    echo "Signing application " & path
    for file in walkDirRec(path):
        if file.endsWith(".cstemp"):
            file.removeFile
        elif file.endsWith(".jnilib") or file.endsWith(".dylib") or file.endsWith(otherExts) or file.cstring.needsSigning:
            signFile(file)
        elif file.endsWith(".jar"):
            signZippedEntries(file, otherExts)
    signFile(path)
    echo " *** Sign successful"
