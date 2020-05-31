import osproc, os, strutils, nim_miniz, tempfile, myexec, autos

{.compile: "fileloader.c".}
proc needsSigning(path:cstring):bool {.importc.}

proc signImpl(path:string, entitlements:string, rootSign:bool): seq[string]

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
    name.deleteLater
    return name

proc signFile(path:string, entitlements:string) =
    myexec "Sign " & (if path.existsDir: "app" else: "file") & " " & path.extractFilename, "codesign --timestamp --deep --force --verify --verbose --options runtime --sign " & ID.quoteShell &
        " --entitlements " & entitlements.quoteShell & " " & path.quoteShell
    myexec "", "codesign --verify --verbose " & path.quoteShell

proc signJarEntries(jarfile:string, entitlements:string) =
    let tempdir = mkdtemp("notr_jar_")
    jarfile.unzip(tempdir)
    let signed = signImpl(tempdir, entitlements, false)
    for file in signed:
        myexec "", "jar -uf " & jarfile.quoteShell & " -C " & tempdir.quoteShell & " " & file
    tempdir.removeDir

proc signImpl(path:string, entitlements:string, rootSign:bool): seq[string] =
    template full(cfile:string):string = joinPath(path, cfile)
    for file in walkDirRec(path, relative = true):
        if file.endsWith(".cstemp"):
            file.full.removeFile
        elif file.endsWith(".jnilib") or file.endsWith(".dylib") or file.full.cstring.needsSigning:
            signFile(file.full, entitlements)
            if not rootSign: result.add file
        elif file.endsWith(".jar"):
            signJarEntries(file.full, entitlements)
            if not rootSign: result.add file
    if rootSign:
        signFile(path, entitlements)

proc sign*(path:string, entitlements:string): seq[string] {.discardable.} = signImpl(path, entitlements, true)
