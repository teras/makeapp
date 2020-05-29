import osproc, os, strutils, nim_miniz, sets, tempfile

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

var entitlements_file:string = ""

proc cleanup*() =
    if entitlements_file!="": entitlements_file.removeFile

proc getDefaultEntitlementFile*(): string =
    let (file,name) = mkstemp(prefix="notr_ent_", mode=fmWrite)
    entitlements_file = name
    file.write(DEFAULT_ENTITLEMENT)
    file.close
    return name

proc signFile(path:string, id:string, entitlements:string, files:var seq[string], verbose:int) :bool =
    let entitlementsCmd = if entitlements == "": "" else: " --entitlements " & entitlements.quoteShell
    let cmd = "codesign --timestamp --deep --force --verify --verbose --options runtime --sign " & id.quoteShell & entitlementsCmd & " " & path.quoteShell
    if verbose>0: echo "▹▹ " & (if verbose<=1: cmd.replace(id, "[ID]") else: cmd)
    files.add(path)
    if execCmd(cmd) != 0:
        return false
    if execCmd("codesign --verify --verbose " & path.quoteShell) != 0:
        return false
    return true

proc endsWith(filename:string, otherExts:HashSet[string]) :bool =
    for ending in otherExts:
        if filename.endsWith(ending):
            return true
    return false

proc signZippedEntries(zipfile:string, id:string, entitlements:string, otherExts:HashSet[string], files:var seq[string],verbose:int) =
    var tempdir = ""
    # Extract and sign files
    var zip:Zip
    if not zip.open(zipfile):
        quit("Unable to open compressed file " & zipfile)
    for i,fname in zip:
        if fname.endsWith(".jnilib") or fname.endsWith(".dylib") or fname.endsWith(otherExts):
            if tempdir=="": tempdir = mkdtemp("notsign_")
            discard zip.extract_file(fname, tempdir)
            if not signFile(tempdir / fname, id, entitlements, files, verbose):
                quit("Unable to sign file " & fname)
    zip.close()
    # Replace extracted files
    if tempdir != "":
        for file in walkDirRec(tempdir, relative=true):
            if execCmd("jar -uf " & zipfile.quoteShell & " -C " & tempdir.quoteShell & " " & file)!=0:
                quit("Errors while updating JAR")
            else: echo zipfile & "!" & file & ": signed"
        tempdir.removeDir

proc sign*(path:string, id:string, entitlements:string, otherExts:HashSet[string], verbose:int) =
    echo "Signing: " & path
    var files:seq[string]
    for file in walkDirRec(path):
        if file.endsWith(".jnilib") or file.endsWith(".dylib") or file.endsWith(otherExts) or file.cstring.needsSigning:
            if not signFile(file, id, entitlements, files, verbose):
                quit("Unable to sign file " & file)
        if file.endsWith(".jar"):
            signZippedEntries(file, id, entitlements, otherExts, files, verbose)
    if not signFile(path, id, entitlements, files, verbose):
        quit("Unable to sign Application " & path)
    for file in files:
        echo "𝓢  " & file
    echo " *** Sign successful"
