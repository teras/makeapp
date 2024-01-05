import os, strutils, myexec, types

#{.compile: "fileloader.c".}
#proc needsSigning(path:cstring):bool {.importc, used.}
#parameter is file.full.cstring.needsSigning

proc notarizeMacOS*(path:string) =
  myexec "Notarize file " & path.extractFilename, "rcodesign", "notary-submit", "--api-key-file", NOTARY, "--staple", path

proc signMacOS*(path:string) =
  let ftype = if path.dirExists: "directory" elif path.endsWith(".dmg"): "DMG file" else: "file"
  myexec "Sign " & ftype & " " & path.extractFilename & " ", "rcodesign", "sign", "--p12-file", P12FILE, "--p12-password-file", P12PASS, "--code-signature-flags", "runtime", path

proc signWindows(os:OSType, target,timestamp,name,url:string) =
  echo "SIGN UNDER WINDOWS NOT SUPPORTED YET :'("

proc signApp*(os:seq[OSType], target, timestamp, name, url:string) =
  for cos in os:
    case cos:
      of pMacos:
        signMacOS(target)
      of pWin32,pWin64:
        signWindows(cos, target, timestamp, name, url)
      else: discard
