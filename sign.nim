import os, strutils, nim_miniz, myexec, autos, helper, types

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

proc getDefaultEntitlementFile*(): string = randomFile(DEFAULT_ENTITLEMENT)

proc signFile(path:string, entitlements:string) =
  myexec "Sign " & (if path.existsDir: "app" else: "file") & " " & path.extractFilename, 
    "codesign", "--timestamp", "--deep", "--force", "--verify", "--verbose", "--options", "runtime", "--sign", ID, "--entitlements", entitlements, path
  myexec "", "codesign", "--verify", "--verbose", path

proc signJarEntries(jarfile:string, entitlements:string) =
  let tempdir = randomDir()
  jarfile.unzip(tempdir)
  let signed = signImpl(tempdir, entitlements, false)
  for file in signed:
    myexec "", "jar", "-uf", jarfile, "-C", tempdir, file

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

proc sign(path:string, entitlements:string) = discard signImpl(path, entitlements, true)

proc sign*(os:seq[OSType], target:string, entitlements:string) =
  for cos in os:
    var dest = cos.findApp(if target != "": target else: getCurrentDir())
    if dest == "": dest = findDmg(if dest != "": dest else: getCurrentDir())
    if dest == "": kill("No target file provided")
    safedo: sign(target, entitlements)
