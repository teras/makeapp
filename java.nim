import strutils, sequtils, os, autos, myexec, helper, types, uri, algorithm, mactemplate

# The relative path where the copied app is found
const APPDIR = "app"

# The java modules are hard coded into the Docker file

proc getAssocDef(res:Resource, ostype:OSType, assoc:Assoc): string =
  var def:string
  proc addIf(label:string, value:string) =
    if value != "":
      def.add label
      def.add "="
      def.add value
      def.add "\n"
  "extension".addIf assoc.extension
  "mime-type".addIf assoc.mime
  "description".addIf assoc.description
  "icon".addIf res.icon(assoc.extension, ostype)
  return def

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
        elif system.hostCPU == "arm64":
          os.add pLinuxArm64
        elif system.hostCPU == "arm":
          os.add pLinuxArm32
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
    kill "No destination operating system requested"
  return os.deduplicate

template idx(params:seq[string], idx:int):string =
  if idx>=params.len: "" else: params[idx]

proc findAccociations*(assoc:seq[string], res:Resource): seq[Assoc] =
  for entry in assoc:
    let parts = entry.split(':')
    if parts.len > 3: kill "Too many parameters when defining associations"
    let
      ext = checkParam(parts.idx(0).strip, "No extension given")
      mime = parts.idx(1).strip
      descr = parts.idx(2).strip
    result.add Assoc(extension:ext, description:descr, mime:mime)

proc getJvmOpts*(opts:seq[string]): seq[string] =
  for opt in opts:
    if opt == "": discard
    elif opt == "DEFAULT":
      result.add "-Dawt.useSystemAAFontSettings=on"
      result.add "-Dswing.aatext=true"
    else:
      result.add opt

proc constructId*(url,vendor,name:string): string =
  proc norm(name:string):string {.inline.} = name.splitWhitespace.join.toLowerAscii
  if url == "":
    return "app." & vendor.norm & "." & name.norm
  else:
    var parts = url.parseUri.hostname.split(".")
    if parts.len>0 and parts[0]=="www": parts.delete(0)
    return parts.reversed.join(".") & "." & name.norm

proc copyAppFiles(input, dest:string) {.inject.} =
  dest.createDir
  if not dest.dirExists:
    kill "Unable to create direcotry " & dest
  if input.dirExists:
    merge dest, input
  elif input.fileExists:
    copyFile(input, dest/(input.extractFilename))

proc extractRuntime(ostype:OSType, output:string) =
  podman "Extract " & $ostype & " JRE", "-v", output & ":/target", "crossmob/jre", "sh", "-c" ,
    "cp -a /java/" & ostype.jrearch & " /target" & " && mv /target/" & ostype.jrearch & " /target/runtime" & dockerChown("/target/runtime")

proc makeWindows(output:string, res:Resource, name, version, input, jarname:string,
    jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string, ostype:OSType):string =
  let bits = ostype.bits
  let exec = name & ".exe"
  let cpu = if bits==32: "i386" else: "amd64"
  let strip = if bits==32: "i686-w64-mingw32-strip" else: "x86_64-w64-mingw32-strip"
  let dest = output / name & "." & ostype.appx
  copyAppFiles(input, dest/APPDIR)
  let longversion = "1.0.0.0"
  let execOut = randomDir()
  if icon != "": copyFile(icon, execOut / "appicon.ico")
  podman "Create " & $ostype & " executable", "-v", execOut & ":/root/target", "crossmob/javalauncher", "bash", "-c",
    "nim c -d:release --opt:size --passC:-Iinclude --passC:-Iinclude/windows -d:mingw -d:APPNAME=\"" & name & "\"" &
      " -d:COMPANY=\"" & vendor & "\" -d:DESCRIPTION=\"" & description & "\" -d:APPVERSION=" & version &
      " -d:LONGVERSION=" & longversion & " -d:COPYRIGHT=\"" & "(C) "&vendor & "\"" &
      " -d:JREPATH=runtime -d:JARPATH=" & APPDIR & "/" & jarname &
      (if icon=="":"" else: " -d:ICON=target/appicon.ico") &
      " --app:gui --cpu:" & cpu & " \"-o:target/" & exec & "\" javalauncher ; " & strip & " \"target/" & exec & "\"" &
      dockerChown("target/" & exec) 
  copyFile(execOut / exec, dest / exec)
  extractRuntime ostype, dest
  return dest/APPDIR

# https://bugs.launchpad.net/qemu/+bug/1805913
proc makeLinux(output:string, res:Resource, name, version, input, jarname:string,
    jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string, ostype:OSType):string =
  let dest = output / name.safe & "." & ostype.appx
  copyAppFiles(input, dest/APPDIR)
  let execOut = randomDir()
  let compileFlags = if ostype==pLinuxArm32: "--cpu:arm --os:linux" elif ostype==pLinuxArm64: "--cpu:arm64 --os:linux" else: ""
  let strip = if ostype==pLinuxArm32: "arm-linux-gnueabi-strip" elif ostype==pLinuxArm64: "aarch64-linux-gnu-strip" else: "strip"
  let fixArm =
    if ostype==pLinuxArm32:
      " && patchelf --set-interpreter /lib/ld-linux-armhf.so.3 target/AppRun"
    elif ostype==pLinuxArm64:
      " && patchelf --set-interpreter /lib/ld-linux-aarch64.so.1 target/AppRun"
    else: ""
  podman "Create " & $ostype & " executable", "-v", execOut & ":/root/target", "crossmob/javalauncher", "bash", "-c",
    "nim c -d:release --opt:size --passC:-Iinclude --passC:-Iinclude/linux " & compileFlags & " -d:JREPATH=runtime -d:JARPATH=" &
      APPDIR & "/" & jarname & " -o:target/AppRun javalauncher ; " & strip & " target/AppRun" & dockerChown("target/AppRun") & fixArm
  copyFileWithPermissions execOut / "AppRun", dest / "AppRun"
  extractRuntime ostype, dest
  return dest/APPDIR

proc makeMacos(output:string, res:Resource, name, version, input, jarname:string,
    jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string):string =
  let dest = output / name & "." & pMacos.appx / "Contents"
  let macos = dest/"MacOS"
  let resources = dest/"Resources"
  macos.createDir
  resources.createDir
  block makeExec: # macOS
    let exec = macos/name
    exec.writeFile LAUNCHER
    exec.makeExec
  block makeApp:  # app
    copyAppFiles(input, dest/APPDIR)
    (dest/APPDIR/name&".cfg").writeFile getCfg(name,version,identifier,jarname,dest/APPDIR)
    (dest/APPDIR/".jpackage.xml").writeFile getJpackageXML(name,version)
  if icon.fileExists: # Resources
    icon.copyFile(resources/name&".icns")
  (dest/"Info.plist").writeFile getInfoPlist(name,identifier,version,"(C) "&vendor)
  (dest/"PkgInfo").writeFile "APPL????"
  extractRuntime OSType.pMacos, dest  # runtime
  return dest/APPDIR

proc makeGeneric(output, name, version, input, jarname:string):string =
  let cname = name.toLowerAscii
  let dest = output / cname & "-" & version & "." & pGeneric.appx
  copyAppFiles(input, dest/APPDIR)
  let launcherfile = dest / cname.safe
  writeFile launcherfile, """
#!/bin/sh
cd "`dirname \"$0\"`"

for p in "$@"; do
  case "$p" in
    -D*) JAVA_LAUNCHER_PARAM="$JAVA_LAUNCHER_PARAM $p" ;;
      *) APPL_LAUNCHER_PARAM="$APPL_LAUNCHER_PARAM $p" ;;
  esac
done

java $JAVA_LAUNCHER_PARAM -jar """" & APPDIR & "/" & jarname & """" $APPL_LAUNCHER_PARAM
"""
  launcherfile.makeExec
  writeFile dest / cname & ".bat", """
@echo off

:loop
if "%~1"=="" goto afterloop
set "p=%~1"
if "!p:~0,2!"=="-D" (
    set "JAVA_LAUNCHER_PARAM=!JAVA_LAUNCHER_PARAM! %1"
) else (
    set "APPL_LAUNCHER_PARAM=!APPL_LAUNCHER_PARAM! %1"
)
shift
goto loop

:afterloop
start javaw %JAVA_LAUNCHER_PARAM% -jar """" & APPDIR & "\\" & jarname & """" %APPL_LAUNCHER_PARAM%
"""
  return dest/APPDIR

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

proc makeJava*(os:seq[OSType], output:string, res:Resource, name, version, input, jarname:string, jvmopts:seq[string],
    associations:seq[Assoc], extra, vendor, description, identifier, url, jdkhome:string) =
  let
    jdkhome = if jdkhome == "": getEnv("JAVA_HOME") else: jdkhome
    extra = extra.absolutePath
    splash = "" #resources.resource("splash.png")
  for cos in os:
    let icon = res.icon("app", cos)
    let appout = case cos:
      of pMacos: makeMacos(output, res, name, version, input, jarname, jvmopts, associations, icon, splash, vendor, description, identifier, url, jdkhome)
      of pWin32, pWin64: makeWindows(output, res, name, version, input, jarname, jvmopts, associations, icon, splash, vendor, description, identifier, url, jdkhome, cos)
      of pLinux64, pLinuxArm32, pLinuxArm64: makeLinux(output, res, name, version, input, jarname, jvmopts, associations, icon, splash, vendor, description, identifier, url, jdkhome, cos)
      of pGeneric: makeGeneric(output, name, version, input, jarname)
    if extra != "": copyExtraFiles(appout, extra, cos)
