import strutils, sequtils, os, autos, myexec, helper

type OSType* = enum
  pMacos, pLinux32, pLinux64, pWin32, pWin64

type Assoc* = object
  extension*: string
  description*: string
  mime*: string

proc `$`*(ostype:OSType):string = system.`$`(ostype).substr(1).toLowerAscii

proc typesList*():string = OSType.mapIt($it).join(", ")

proc icon(ostype:OSType, filename:string):string = return case ostype:
  of pMacos: filename & ".icns"
  of pWin32, pWin64: filename & ".ico"
  of pLinux32, pLinux64: filename & ".png"

proc resource*(resourcedir:string, resource:string):string =
  let path = if resourcedir == "": resource else: resourcedir / resource
  return if path.fileExists: path else: ""

proc getAssocDef(resources:string, ostype:OSType, assoc:Assoc): string =
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
  "icon".addIf res.resource(ostype.icon(assoc.extension))
  return res

proc findOS*(list:string):seq[OSType] =
  var os:seq[OSType]
  let list = if list=="": "system" else: list
  for part in list.split(','):
    if part == "system":
      when system.hostOS == "macosx":
        os.add pMacos
      elif system.hostOS == "linux":
        if system.hostCPU == "amd64":
          os.add pLinux64
        elif system.hostCPU == "i386":
          os.add pLinux32
        else:
          kill "Unsupported Linux CPU type"
      elif system.hostOS == "windows":
        if system.hostCPU == "amd64":
          os.add pWin64
        else:
          os.add pWin32
      else:
        kill "Unsupported operating system"
    else:
      var added = false
      for otype in OSType:
        if part.strip.toLowerAscii == $otype :
          os.add(otype)
          added = true
          break
      if not added and part != "":
        kill "Unkown package type " & part.strip
  if os.len == 0:
    kill "No destination opperatin system requested"
  return os.deduplicate

template idx(params:seq[string], idx:int):string =
  if idx>=params.len: "" else: params[idx]

proc findAccociations*(assoc:seq[string], res:string): seq[Assoc] =
  for entry in assoc:
    let parts = entry.split(':')
    if parts.len > 3: kill "Too many parameters when defining associations"
    let
      ext = checkParam(parts.idx(0).strip, "No extension given")
      mime = parts.idx(1).strip
      descr = parts.idx(2).strip
    result.add Assoc(extension:ext, description:descr, mime:mime)

proc getJar*(jar:string, appdir:string): string =
    if jar == "": kill "No source JAR provided"
    if not jar.endsWith(".jar"): kill "JAR file should end with \".jar\" extension, given: " & jar
    var jar = if jar.isAbsolute: jar else: appdir / jar
    jar = jar.absolutePath
    jar.normalizePath
    if not jar.startsWith(appdir): kill "JAR at location " & jar & " doesn't seem to be under directory " & appdir
    if not jar.fileExists: kill "Unable to locate file " & jar
    return jar.relativePath(appdir)

proc getJvmOpts*(opts:seq[string]): seq[string] =
  for opt in opts:
    if opt == "": discard
    elif opt == "DEFAULT":
      result.add "-Dawt.useSystemAAFontSettings=on"
      result.add "-Dswing.aatext=true"
    else:
      result.add opt

proc constructId*(username:string, name:string): string = "app." & username.toLowerAscii & "." & name.splitWhitespace.join.toLowerAscii

proc makeWindows(output:string, resources:string, name:string, version:string, appdir:string, jar:string,
    modules:string, jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string, bits32:bool):string =
  let arch = if bits32:"32" else:"64"
  let exec = name & ".exe"
  let cpu = if bits32: "i386" else: "amd64"
  let strip = if bits32: "i686-w64-mingw32-strip" else: "x86_64-w64-mingw32-strip"
  let dest = output / name & ".w" & arch
  merge dest, appdir
  let longversion = "1.0.0.0"
  let execOut = randomDir()
  if icon != "": copyFile(icon, execOut / "appicon.ico")
  myexec "Create executable", "docker", "run", "--rm", "-v", execOut & ":/root/target", "crossmob/javalauncher", "bash", "-c",
    "nim c -d:release --opt:size --passC:-Iinclude --passC:-Iinclude/windows -d:mingw -d:APPNAME=\"" & name & "\"" &
      " -d:COMPANY=\"" & vendor & "\" -d:DESCRIPTION=\"" & description & "\" -d:APPVERSION=" & version &
      " -d:LONGVERSION=" & longversion & " -d:COPYRIGHT=\"" & "(C) "&vendor & "\"" &
      (if icon=="":"" else: " -d:ICON=target/appicon.ico") &
      " --app:gui --cpu:" & cpu & " \"-o:target/" & exec & "\" javalauncher ; " & strip & " \"target/" & exec & "\""
  copyFile(execOut / exec, dest / exec)
  myexec "Extract JRE", "docker", "run", "--rm", "-v", dest & ":/usr/src/myapp", "crossmob/jdk", "wine" & arch,
    "/java/win" & arch & "/current/bin/jlink", "--add-modules", modules, "--output", "/usr/src/myapp/jre", "--no-header-files",
    "--no-man-pages", "--compress=1"
  return dest

proc makeLinux(output:string, resources:string, name:string, version:string, appdir:string, jar:string,
    modules:string, jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string, arch:string):string =
  discard

proc makeWin32(output:string, resources:string, name:string, version:string, appdir:string, jar:string,
    modules:string, jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string):string =
  makeWindows(output, resources, name, version, appdir, jar, modules, jvmopts, associations, icon, splash, vendor, description, jdkhome, identifier, url, true)
  
proc makeWin64(output:string, resources:string, name:string, version:string, appdir:string, jar:string,
    modules:string, jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string):string =
  makeWindows(output, resources, name, version, appdir, jar, modules, jvmopts, associations, icon, splash, vendor, description, jdkhome, identifier, url, false)

proc makeLinux32(output:string, resources:string, name:string, version:string, appdir:string, jar:string,
    modules:string, jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string):string =
  makeLinux(output, resources, name, version, appdir, jar, modules, jvmopts, associations, icon, splash, vendor, description, jdkhome, identifier, url, "32")
  
proc makeLinux64(output:string, resources:string, name:string, version:string, appdir:string, jar:string,
    modules:string, jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string):string =
  makeLinux(output, resources, name, version, appdir, jar, modules, jvmopts, associations, icon, splash, vendor, description, jdkhome, identifier, url, "64")

proc makeMacos(output:string, resources:string, name:string, version:string, appdir:string, jar:string,
    modules:string, jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string):string =
  when system.hostOS != "macosx": kill "Create of a macOS package is supported only under macOS itself"
  let jpackage = if jdkhome == "": "jpackage" else:
    let possible = jdkhome / "bin" / "jpackage"
    if not possible.fileExists: kill "Unable to locate jpackage using JAVA_HOME " & jdkhome
    possible
  var args = @[jpackage, "--app-version", version, "--name", name, "--input", appdir, "--add-modules", modules,
      "--main-jar", jar, "--dest", output, "--type", "app-image",
      "--copyright", "(C) "&vendor, "--description", description, "--vendor", vendor,
      "--mac-package-identifier", identifier, "--mac-package-name", name]
  for assoc in associations:
    args.add "--file-associations"
    args.add randomFile(getAssocDef(resources, pMacos, assoc))
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
  let app = output / name & ".app"
  (app & "/Contents/runtime/Contents/MacOS").removeDir(true)
  return app & "/Contents/app"

proc copyExtraFiles(app:string, extra:string, ostype:OSType) =
  let common = extra / "common"
  if common.dirExists: merge(app, common)
  let osname = $ostype
  if osname.startsWith("win"):
    let winextra = extra / "windows"
    if winextra.dirExists: merge(app, winextra)
  if osname.startsWith("linux"):
    let linextra = extra / "linux"
    if linextra.dirExists: merge(app, linextra)
  let current = extra / osname
  if current.dirExists: merge(app, current)

proc makeJava*(os:seq[OSType], output:string, resources:string, name:string, version:string, appdir:string, jar:string,
    modules:string, jvmopts:seq[string], associations:seq[Assoc], extra:string, vendor:string,
    description:string, identifier:string, url:string, jdkhome:string) =
  let
    jdkhome = if jdkhome == "": getEnv("JAVA_HOME") else: jdkhome
    extra = extra.absolutePath
    splash = "" #resources.resource("splash.png")
  for cos in os:
    let icon = resources.resource(cos.icon("app"))
    let appout = case cos:
      of pMacos: makeMacos(output, resources, name, version, appdir, jar, modules, jvmopts, associations, icon, splash, vendor, description, identifier, url, jdkhome)
      of pWin32: makeWin32(output, resources, name, version, appdir, jar, modules, jvmopts, associations, icon, splash, vendor, description, identifier, url, jdkhome)
      of pWin64: makeWin64(output, resources, name, version, appdir, jar, modules, jvmopts, associations, icon, splash, vendor, description, identifier, url, jdkhome)
      of pLinux32: makeLinux32(output, resources, name, version, appdir, jar, modules, jvmopts, associations, icon, splash, vendor, description, identifier, url, jdkhome)
      of pLinux64: makeLinux64(output, resources, name, version, appdir, jar, modules, jvmopts, associations, icon, splash, vendor, description, identifier, url, jdkhome)
    if extra != "": copyExtraFiles(appout, extra, cos)
