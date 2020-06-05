import strutils, sequtils, os, autos, myexec

type OSType* = enum
  pMacos, pLinux, pWin32, pWin64

type Assoc* = object
  extension*: string
  description*: string
  mime*: string
  icon*: string

proc `$`*(ostype:OSType):string = system.`$`(ostype).substr(1).toLowerAscii

proc `$`*(assoc:Assoc):string =
  var res:string
  proc addIf(label:string, value:string) =
    if value != "":
      res.add label
      res.add "="
      res.add value
      res.add "\n"
  "extension".addIf assoc.extension
  "mime-type".addIf assoc.mime
  "description".addIf assoc.description
  "icon".addIf assoc.icon
  return res

proc findOS*(list:string):seq[OSType] =
  var os:seq[OSType]
  for part in list.split(','):
    var added = false
    for otype in OSType:
      if part.strip.toLowerAscii == $otype :
        os.add(otype)
        added = true
        break
    if not added and part != "":
      kill "Unkown package type " & part.strip
  if os.len == 0:
    when system.hostOS == "macosx":
      os.add pMacos
    elif system.hostOS == "linux":
      os.add pLinux
    elif system.hostOS == "windows":
      os.add pWin32
      os.add pWin64
    else:
      kill "Unsupported operating system"
  return os.deduplicate

template idx(params:seq[string], idx:int):string =
  if idx>=params.len: "" else: params[idx]

proc findAccociations*(assoc:seq[string]): seq[Assoc] =
  for entry in assoc:
    let parts = entry.split(':')
    if parts.len > 4: kill "Too many parameters when defining associations"
    let acc = Assoc(extension:parts.idx(0).strip, description:parts.idx(1).strip, mime:parts.idx(2).strip, icon:parts.idx(3))
    if acc.extension == "": kill "No extension provided"
    result.add acc

proc getJar*(jar:string, applib:string): string =
    var jar = if jar.isAbsolute: jar else: applib / jar
    if jar == "": kill "No source JAR provided"
    if not jar.endsWith(".jar"): kill "JAR file should end with \".jar\" extension, given: " & jar
    jar = jar.absolutePath
    jar.normalizePath
    if not jar.startsWith(applib): kill "JAR at location " & jar & " doesn't seem to be under directory " & applib
    if not jar.fileExists: kill "Unable to locate file " & jar
    return jar.relativePath(applib)

proc getJvmOpts*(opts:seq[string]): seq[string] =
  for opt in opts:
    if opt == "": discard
    elif opt == "DEFAULT":
      result.add "-Dawt.useSystemAAFontSettings=on"
      result.add "-Dswing.aatext=true"
    else:
      result.add opt

proc constructId*(username:string, name:string): string = "app." & username.toLowerAscii & "." & name.splitWhitespace.join.toLowerAscii

proc makeWindows(output:string, resources:string, name:string, version:string, applib:string, jar:string,
    modules:string, jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string, arch:string) =
  discard

proc makeWin32(output:string, resources:string, name:string, version:string, applib:string, jar:string,
    modules:string, jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string) =
  makeWindows(output, resources, name, version, applib, jar, modules, jvmopts, associations, icon, splash, vendor, description, jdkhome, identifier, url, "32")
  
proc makeWin64(output:string, resources:string, name:string, version:string, applib:string, jar:string,
    modules:string, jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string) =
  makeWindows(output, resources, name, version, applib, jar, modules, jvmopts, associations, icon, splash, vendor, description, jdkhome, identifier, url, "64")

proc makeLinux(output:string, resources:string, name:string, version:string, applib:string, jar:string,
    modules:string, jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string) =
  discard

proc makeMacos(output:string, resources:string, name:string, version:string, applib:string, jar:string,
    modules:string, jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string) =
  when system.hostOS != "macosx": kill "Create of a macOS package is supported only under macOS itself"

  let jpackage = if jdkhome == "": "jpackage" else:
    let possible = jdkhome / "bin" / "jpackage"
    if not possible.fileExists: kill "Unable to locate jpackage using JAVA_HOME " & jdkhome
    possible
  var args = @[jpackage, "--app-version", version, "--name", name, "--input", applib, "--add-modules", modules,
      "--main-jar", jar, "--dest", output, "--type", "app-image",
      "--copyright", "(C) "&vendor, "--description", description, "--vendor", vendor,
      "--mac-package-identifier", identifier, "--mac-package-name", name]
  for assoc in associations:
    let assoc = randomFile($assoc)
    args.add "--file-associations"
    args.add assoc
  for jvmopt in jvmopts:
    args.add "--java-options"
    args.add jvmopt
  if splash != "":
    args.add "--java-options"
    args.add "-splash:$APPDIR/" & splash
  if icon != "":
    args.add "--icon"
    args.add icon
  myexec "Use jpackage to create Java package", args
  (name & ".app/Contents/runtime/Contents/MacOS/libjli.dylib").removeFile


proc makeJava*(os:seq[OSType], output:string, resources:string, name:string, version:string, applib:string, jar:string,
    modules:string, jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string, vendor:string,
    description:string, identifier:string, url:string, jdkhome:string) =
  let jdkhome = if jdkhome == "": getEnv("JAVA_HOME") else: jdkhome
  for cos in os:
    case cos:
      of pMacos: makeMacos(output, resources, name, version, applib, jar, modules, jvmopts, associations, icon, splash, vendor, description, identifier, url, jdkhome)
      of pWin32: makeWin32(output, resources, name, version, applib, jar, modules, jvmopts, associations, icon, splash, vendor, description, identifier, url, jdkhome)
      of pWin64: makeWin64(output, resources, name, version, applib, jar, modules, jvmopts, associations, icon, splash, vendor, description, identifier, url, jdkhome)
      of pLinux: makeLinux(output, resources, name, version, applib, jar, modules, jvmopts, associations, icon, splash, vendor, description, identifier, url, jdkhome)