import os, strutils, nim_miniz, myexec, autos, helper, types, algorithm

{.compile: "fileloader.c".}
proc needsSigning(path:cstring):bool {.importc.}

proc signMacOSImpl(path:string, entitlements:string, rootSign:bool): seq[string]

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
  myexec "", "codesign", "--timestamp", "--force", "--verify", "--verbose", "--options", "runtime", "--sign", ID, "--entitlements", entitlements, path
  myexec "", "codesign", "-vvv", "--deep", "--strict", "--verbose", path

proc signMacOSJarEntries(jarfile:string, entitlements:string) =
  let tempdir = randomDir()
  jarfile.unzip(tempdir)
  let signed = signMacOSImpl(tempdir, entitlements, false)
  for file in signed:
    myexec "", "jar", "-uf", jarfile, "-C", tempdir, file

proc signMacOSImpl(path:string, entitlements:string, rootSign:bool): seq[string] =
  template full(cfile:string):string = joinPath(path, cfile)
  var deferSign:seq[string] = @[]
  for file in walkDirRec(path, relative = true):
    if file.endsWith(".cstemp"):
      file.full.removeFile
    elif file.endsWith(".jnilib") or file.endsWith(".dylib") or file.full.cstring.needsSigning:
      deferSign.add(file)
      if not rootSign: result.add file
    elif file.endsWith(".jar"):
      signMacOSJarEntries(file.full, entitlements)
      if not rootSign: result.add file
  deferSign.sort  # That's a really dirty trick to handle signing requests. In reality we need dependency hierarchy priority.
  for deferred in deferSign:
    signFile(deferred.full, entitlements)
  if rootSign:
    signFile(path, entitlements)

proc signMacOS(path:string, entitlements:string) =
  info "Sign " & (if path.dirExists: "app" else: "file") & " " & path.extractFilename
  discard signMacOSImpl(path, entitlements, true)

proc signWindows(os:OSType, target,p12file,timestamp,name,url:string) =
  let unsigned = (if target.endsWith(".exe"): target.substr(0,target.len-5) else:target) & ".unsigned.exe"
  moveFile target, unsigned
  if timestamp=="":
    myexec "Sign installer", "osslsigncode","sign", "-pkcs12", p12file, "-pass", P12PASS, 
      "-n", name & " Installer", "-i", url, "-in", unsigned, "-out", target
  else:
    myexec "Sign installer", "osslsigncode","sign", "-pkcs12", p12file, "-pass", P12PASS, 
      "-n", name & " Installer", "-i", url, "-t", timestamp, "-in", unsigned, "-out", target
  myexecprobably "", "osslsigncode", "verify", target
  unsigned.removeFile

proc sign*(os:seq[OSType], target, entitlements, p12file, timestamp, name, url:string) =
  for cos in os:
    case cos:
      of pMacos:
        var dest = cos.findApp(if target != "": target else: getCurrentDir())
        if dest == "": dest = findDmg(if dest != "": dest else: getCurrentDir())
        if dest == "": kill("No target file provided")
        signMacOS(target, entitlements)
      of pWin32,pWin64:
        signWindows(cos, target, p12file, timestamp, name, url)
      else: discard
