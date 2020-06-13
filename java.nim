import strutils, sequtils, os, autos, myexec, helper, types

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
    vendor:string, description:string, identifier:string, url:string, jdkhome:string, singlejar:bool, ostype:OSType):string =
  let bits = ostype.bits
  let exec = name & ".exe"
  let cpu = if bits==32: "i386" else: "amd64"
  let strip = if bits==32: "i686-w64-mingw32-strip" else: "x86_64-w64-mingw32-strip"
  let dest = output / name & "." & ostype.appx
  dest.createDir
  if singlejar: copyFile(appdir / jar, dest / jar)
  else: merge dest, appdir
  let longversion = "1.0.0.0"
  let execOut = randomDir()
  if icon != "": copyFile(icon, execOut / "appicon.ico")
  myexec "Create " & $ostype & " executable", "docker", "run", "--rm", "-v", execOut & ":/root/target", "crossmob/javalauncher", "bash", "-c",
    "nim c -d:release --opt:size --passC:-Iinclude --passC:-Iinclude/windows -d:mingw -d:APPNAME=\"" & name & "\"" &
      " -d:COMPANY=\"" & vendor & "\" -d:DESCRIPTION=\"" & description & "\" -d:APPVERSION=" & version &
      " -d:LONGVERSION=" & longversion & " -d:COPYRIGHT=\"" & "(C) "&vendor & "\"" &
      " -d:JREPATH=jre -d:JARPATH=" & jar & 
      (if icon=="":"" else: " -d:ICON=target/appicon.ico") &
      " --app:gui --cpu:" & cpu & " \"-o:target/" & exec & "\" javalauncher ; " & strip & " \"target/" & exec & "\""
  copyFile(execOut / exec, dest / exec)
  myexec "Extract " & $ostype & " JRE", "docker", "run", "--rm", "-v", dest & ":/usr/src/myapp", "crossmob/jdkwin", "wine" & $bits,
    "/java/win" & $bits & "/current/bin/jlink", "--add-modules", modules, "--output", "/usr/src/myapp/jre", "--no-header-files",
    "--no-man-pages", "--compress=1"
  return dest

# https://bugs.launchpad.net/qemu/+bug/1805913
proc makeLinux(output:string, resources:string, name:string, version:string, appdir:string, jar:string,
    modules:string, jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string, singlejar:bool, ostype:OSType):string =
  let dest = output / name & "." & ostype.appx
  dest.createDir
  if singlejar: copyFile(appdir / jar, dest / jar)
  else: merge dest, appdir
  let execOut = randomDir()
  let imageFlavour = if ostype==pLinuxArm32: "armv7l-centos-jdk-14.0.1_7-slim"
    elif ostype==pLinuxArm64: "aarch64-centos-jdk-14.0.1_7-slim"
    else: "x86_64-centos-jdk-14.0.1_7-slim"
  let compileFlags = if ostype==pLinuxArm32: "--cpu:arm --os:linux" elif ostype==pLinuxArm64: "--cpu:arm64 --os:linux" else: ""
  let strip = if ostype==pLinuxArm32: "arm-linux-gnueabi-strip" elif ostype==pLinuxArm64: "aarch64-linux-gnu-strip" else: "strip"
  myexec "Create " & $ostype & " executable", "docker", "run", "--rm", "-v", execOut & ":/root/target", "crossmob/javalauncher", "bash", "-c",
    "nim c -d:release --opt:size --passC:-Iinclude --passC:-Iinclude/linux " & compileFlags & " -d:JREPATH=jre -d:JARPATH=" & jar & 
      " -o:target/AppRun javalauncher ; " & strip & " target/AppRun"
  copyFileWithPermissions execOut / "AppRun", dest / "AppRun"
  myexec "Extract " & $ostype & " JRE", "docker", "run", "--rm", "-v", dest & ":/usr/src/myapp", "adoptopenjdk/openjdk14:" & imageFlavour, 
    "jlink", "--add-modules", modules, "--output", "/usr/src/myapp/jre", "--no-header-files",
    "--no-man-pages", "--compress=1"
  return dest

proc makeMacos(output:string, resources:string, name:string, version:string, appdir:string, jar:string,
    modules:string, jvmopts:seq[string], associations:seq[Assoc], icon:string, splash:string,
    vendor:string, description:string, identifier:string, url:string, jdkhome:string, singlejar:bool):string =
  when system.hostOS != "macosx": kill "Create of a macOS package is supported only under macOS itself"
  let jpackage = if jdkhome == "": "jpackage" else:
    let possible = jdkhome / "bin" / "jpackage"
    if not possible.fileExists: kill "Unable to locate jpackage using JAVA_HOME " & jdkhome
    possible
  let inputdir = if singlejar:
      let cdir = randomDir()
      copyFile(appdir / jar, cdir / jar)
      cdir
    else: appdir
  var args = @[jpackage, "--app-version", version, "--name", name, "--input", inputdir, "--add-modules", modules,
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
  let app = output / name & "." & pMacos.appx
  (app & "/Contents/runtime/Contents/MacOS").removeDir(true)
  return app & "/Contents/app"

proc makeGeneric(output, name, version, appdir, jar:string, singlejar:bool):string =
  let cname = name.toLowerAscii
  let dest = output / cname & "-" & version & "." & pGeneric.appx
  dest.createDir
  if singlejar: copyFile(appdir / jar, dest / jar)
  else: merge dest, appdir

  let launcherfile = dest / cname
  let launcher = """
#!/bin/sh
cd "`dirname \"$0\"`"
java -jar """" & jar & """"
"""
  writeFile launcherfile, launcher
  launcherfile.setFilePermissions({fpUserExec, fpUserRead, fpUserWrite, fpGroupExec, fpGroupRead, fpOthersExec, fpOthersRead})
  return dest

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

proc makeJava*(os:seq[OSType], output, resources, name, version, appdir, jar, modules:string, jvmopts:seq[string],
    associations:seq[Assoc], extra, vendor, description, identifier, url, jdkhome:string, singlejar:bool) =
  let
    jdkhome = if jdkhome == "": getEnv("JAVA_HOME") else: jdkhome
    extra = extra.absolutePath
    splash = "" #resources.resource("splash.png")
  for cos in os:
    let icon = resources.resource(cos.icon("app"))
    let appout = case cos:
      of pMacos: makeMacos(output, resources, name, version, appdir, jar, modules, jvmopts, associations, icon, splash, vendor, description, identifier, url, jdkhome, singlejar)
      of pWin32, pWin64: makeWindows(output, resources, name, version, appdir, jar, modules, jvmopts, associations, icon, splash, vendor, description, identifier, url, jdkhome, singlejar, cos)
      of pLinux64, pLinuxArm32, pLinuxArm64: makeLinux(output, resources, name, version, appdir, jar, modules, jvmopts, associations, icon, splash, vendor, description, identifier, url, jdkhome, singlejar, cos)
      of pGeneric: makeGeneric(output, name, version, appdir, jar, singlejar)
    if extra != "": copyExtraFiles(appout, extra, cos)
