import myexec, nim_miniz, os, strutils, autos, sign, helper, types, sequtils, strformat, sugar

const BACKGROUND_DMG = when system.hostOS == "macosx": "background.jpg".readFile else:""
const DMGCONV* = when not defined(macosx): ("dmg").staticRead else: ""

proc findDmgDestination(dest,appname:string): string =
  var found:seq[string]
  for (kind,file) in dest.walkDir(relative=true):
    if kind == pcDir:
      if file==appname:
        info "Found application " & appname
        return dest / file
      elif file.endsWith(".app"):
        found.add(file)
  kill("Unable to locate application \"" & appname & "\", found: " & join(found, ", "))

proc createDMGImpl(os:OSType, givenDmg, output_file, app, name:string, noSign:seq[OSType], entitlements:string)=
  # Define destination mount point
  let volume = "/Volumes/" & randomFile().extractFilename
  let isDmgCustom = not givenDmg.fileExists
  let srcdmg = if isDmgCustom: randomFile() & ".dmg" else: givenDmg

  # Attach destination volume
  myexecQuiet "Detach old volume if any", "hdiutil", "detach", volume
  if isDmgCustom:
    let size = myexec("", "du", "-sk", app).splitWhitespace[0].parseInt + 1000
    myexec "Create new DMG file", "hdiutil", "create", "-volname", name, "-fs", "HFS+", "-size", $size&"k" , "-srcfolder", app, "-fsargs", "-c c=64,a=16,e=16", "-format", "UDRW", srcdmg
  myexec "Attach volume", "hdiutil", "attach", "-readwrite", "-noverify", "-noautoopen", "-mountpoint", volume, srcdmg
  delegateLater(proc () =
    if volume.dirExists: myexec "Detach volume", "hdiutil", "detach", "-force", volume
  )
  let appdest = findDmgDestination(volume, app.extractFilename)
  if isDmgCustom:
    createSymlink("/Applications", volume / "Applications")
    let backgroundDir = volume / ".background"
    backgroundDir.createDir
    (backgroundDir / "background.jpg").writeFile BACKGROUND_DMG
    let osascript = randomFile()
    osascript.writeFile """
      tell application "Finder"
        tell disk """" & volume.extractFilename & """"
          open
          set current view of container window to icon view
          set toolbar visible of container window to false
          set statusbar visible of container window to false
          set the bounds of container window to {400, 100, 820, 440}
          set viewOptions to the icon view options of container window
          set arrangement of viewOptions to not arranged
          set icon size of viewOptions to 92
          set background picture of viewOptions to file ".background:background.jpg"
          set position of item """" & name & """.app" of container window to {95, 175}
          set position of item "Applications" of container window to {330, 175}
          close
          open
          update without registering applications
          delay 2
        end tell
      end tell"""
    myexec "Fix locations", "osascript", osascript
    myexec "", "sync"
  else:
    appdest.removeDir
    appdest.createDir
    info "Copy files"
    merge appdest, app
  let sign = not noSign.contains(os)
  if sign:
    signApp(@[pMacos], appdest, entitlements, "", "", "", "")
  myexec "Detach volume", "hdiutil", "detach", "-force", volume
  myexec "Compress volume", "hdiutil", "convert", srcdmg, "-format", "UDZO", "-imagekey", "zlib-level=9", "-ov", "-o", output_file
  if sign:
    signApp(@[pMacos], output_file, entitlements, "", "", "", "")

proc mountWithUDiskCtrl(image:string):string =
  let devWithDot = myexec("", "udisksctl", "loop-setup", "--file", image).split(" as ")[1]
  let lastDotIndex = devWithDot.rfind(".")
  let devname = devWithDot[0..(lastDotIndex-1)]
  for i in 1..50:
    let infoOut = myexec("", "udisksctl", "info", "-b", devname).splitlines()
    let mountpoints = infoOut.findSubstring("MountPoints:").strip()[12..^1].strip()
    if (mountpoints.len==0):
      sleep(100)
    else:
      if image notin infoOut.findSubstring("BackingFile:"): kill "Device " & devname & " doesn't seem to mount file " & image
      return mountpoints
  kill "Wait timeout for mounted disk " & image

proc createMacosPack(os:OSType, dmg_template, output_file, app, name:string, res:Resource, noSign:seq[OSType], entitlements: string) =
  when defined(macosx):
    let dmg_template = if dmg_template=="": res.path("dmg_mac.zip") else:dmg_template
    if dmg_template!="":
      let tempdir = randomDir()
      info "Unzip template"
      dmg_template.unzip(tempdir)
      for kind,path in tempdir.walkDir:
        if kind == pcFile and path.endsWith(".dmg"):
          createDMGImpl(os, path, output_file, app, name, noSign, entitlements)
          return
      kill("No DMG found in provided file")
    else: createDMGImpl(os, "", output_file, app, name, noSign, entitlements)
  else:
    let dmg_template = if dmg_template=="": res.path("dmg_linux.zip") else:dmg_template
    if dmg_template.isEmptyOrWhitespace :
      echo dmg_template
      myexec "Create "&output_file.extractFilename, podmanExec, "run", "--rm",
        "-v", app.parentDir&":/usr/src/app/src",
        "-v", output_file.parentDir&":/usr/src/app/dest",
        "teras/appimage-builder", "makemac.sh", app.extractFilename, output_file.extractFilename
    else:
      if not output_file.endsWith(".zip") : kill("The reqested MacOS file should end with .zip. Please revise script.")
      let stripped_file = output_file[0..^5]
      let output_file = stripped_file & ".dmg"
      let image = stripped_file & ".uncompressed.dmg"
      let datafiles = randomDir()
      output_file.removeFile
      image.removeFile
      # Start procedure
      dmg_template.unzip(datafiles)
      myexec "", "truncate", "-s", "200M", image
      podman "", "-t", "-v",  image & ":/image.dmg", "teras/appimage-builder", "mkfs.hfsplus" , "-v", name, "/image.dmg"
      let mountdir = mountWithUDiskCtrl(image)
      # Copy template & app files
      merge mountdir, datafiles
      (mountdir/app.extractFilename).createDir
      merge mountdir/app.extractFilename, app
      # Recreate symlink to /Applications
      (mountdir/"Applications").removeFile
      myexec "", "ln", "-s", "/Applications", mountdir
      # unmount, compress and remove uncompressed file
      myexec "", "umount", mountdir
      podman "", "-t",
        "-v", output_file.parentDir & ":/data",
        "teras/appimage-builder", "dmg" ,
        "/data/" & image.extractFilename,
        "/data/" & output_file.extractFilename
      image.removeFile

proc constructISS(os:OSType, app:string, res:Resource, inst_res, name, version, url, vendor:string, associations:seq[Assoc]):string =
  let icon = res.icon("install", os)
  let logo_install = res.path("logo-install.bmp")
  let logo_small = @[res.path("logo-install-small.bmp"),res.path("logo-install-small@2x.bmp")].filter(proc (a:string):bool=a!="")

  var iss = """#define AppName """" & name & """"
#define AppUrl """" & url & """"
#define AppVersion """" & version & """"
#define AppVendor """" & vendor & """"

[Setup]
AppName={#AppName}
DefaultDirName={commonpf}\{#AppName}
DefaultGroupName={#AppName}
AppVersion={#AppVersion}
OutputBaseFilename={#AppName}
OutputDir=.
AppPublisher={#AppVendor}
AppPublisherURL={#AppUrl}
DisableReadyPage=yes
UninstallDisplayIcon={app}\{#AppName}.exe
AllowNoIcons=yes
"""
  if os==pWin64: iss.add "ArchitecturesInstallIn64BitMode=x64\n"
  if icon!="":
    copyFile(icon, inst_res / "install.ico")
    iss.add "SetupIconFile=install.ico\n"
  if logo_install!="":
    copyFile(logo_install, inst_res / "logo-install.bmp")
    iss.add "WizardImageFile=logo-install.bmp\n"
  if logo_small.len>0:
    iss.add "WizardSmallImageFile=" & logo_small.map(proc (a:string):string=a.extractFilename).join(",") & "\n"
    for logo in logo_small:
      copyFile logo, inst_res / logo.extractFilename
  if associations.len>0: iss.add "ChangesAssociations=yes\n"
  iss.add """

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppName}.exe"; WorkingDir: "{app}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\{#AppName}"; Filename: "{app}\{#AppName}.exe"

[Files]
Source:"app\*"; DestDir:"{app}"; Flags: recursesubdirs
"""
  if associations.len>0:
    iss.add "\n[Registry]\n"
    let associco = app / "associco"
    associco.createDir
    for a in associations:
      let key = "{#AppName}" & a.extension.capitalizeAscii
      let descr = if a.description == "": name & " file" else: a.description
      iss.add """
      Root: HKCR; Subkey: ".""" & a.extension & """";                             ValueData: """" & key & """"; Flags: uninsdeletevalue; ValueType: string; ValueName: ""
      Root: HKCR; Subkey: """" & key & """";                    ValueData: """" & descr & """"; Flags: uninsdeletekey; ValueType: string; ValueName: ""
      Root: HKCR; Subkey: """" & key & """\shell\open\command"; ValueData: """ & "\"" & """""{app}\{#AppName}.exe"" ""%1""" & "\"" & """"";        ValueType: string; ValueName: ""
  """
      let aicon = res.icon(a.extension, os)
      if aicon.fileExists:
        copyFile aicon, associco / aicon.extractFilename
        iss.add """    Root: HKCR; Subkey: """" & key & """\DefaultIcon";        ValueData: "{app}\associco\""" & aicon.extractFilename & """,0";               ValueType: string; ValueName: ""
  """
  return iss

proc createWindowsPack(os:OSType, os_template, output_file, app, p12file, timestamp:string, res:Resource, name, version, descr, url, vendor:string, noSign:seq[OSType], associations:seq[Assoc]) =
  let inst_res = randomDir()
  let issContent = if os_template=="": constructISS(os, app, res, inst_res, name, version, url, vendor, associations) else: readFile(os_template)
  writeFile(inst_res / "installer.iss", issContent)
  podman "", "-v", inst_res&":/work", "-v", app&":/work/app", (if asPodman: "teras/innosetup" else: "amake/innosetup"), "installer.iss"
  moveFile inst_res / name & ".exe", output_file
  if not noSign.contains(os):
    signApp(@[os], output_file, "", p12file, timestamp, name, url)

proc createLinuxPack(os:OSType, output_file, gpgdir:string, res:Resource, app, name, version, descr, cat:string, noSign:seq[OSType]) =
  let inst_res = randomDir()
  let cname = name.toLowerAscii.safe
  var desktop = fmt"""[Desktop Entry]
Type=Application
Name={name}
Exec={cname} %u
Categories={cat}
Comment={descr}
"""
  let icon = res.icon("app", os)
  if icon.fileExists:
    copyFile icon, app / cname&".png"
    desktop.add "Icon=" & cname & "\n"
  writeFile app / cname&".desktop", desktop
  # Old version
  # let runtime = if os==pLinuxArm32 or os==pLinuxArm64: "--runtime-file /opt/appimage/runtime-" & os.cpu else:""
  # let signcmd = if not sign: "" else: "gpg-agent --daemon; gpg2 --detach-sign --armor --pinentry-mode loopback --passphrase '" & GPGKEY & "' `mktemp` ; "
  # podman "", "-t", "-v", gpgdir&":/root/.gnupg", "-v", inst_res&":/usr/src/app", "-v", app&":/usr/src/app/" & cname, "teras/appimage-builder",
  #   "bash", "-c", signcmd & "/opt/appimage/AppRun --comp xz " & runtime & " -v " & cname & (if sign:" --sign" else:"") & " -n " & name.safe & ".appimage" &
  #   dockerChown (name.safe & ".appimage")
  let appdir = app.lastPathPart.safe
  podman "", "-t", "-v", inst_res&":/usr/src/app", "-v", app&":/usr/src/app/" & appdir, "teras/appimage-builder",
    "bash", "-c", "export VERSION=" & version & " && /opt/appimage/AppRun " & appdir & dockerChown("*.AppImage")
  let produced =  inst_res.walkDir.toSeq.mapIt(it.path).filter(proc(x:string):bool = x.endsWith(".AppImage"))[0]  # get the actual target filename
  moveFile produced, output_file
  output_file.makeExec

proc createGenericPack(output_file, app:string) =
  myexec "", "tar", "jcvf", output_file, "-C", app.parentDir, app.extractFilename

proc createPack*(os:seq[OSType], os_template:string, outdir, app:string, noSign:seq[OSType], entitlements, p12file, timestamp, gpgdir:string, res:Resource, name, version, descr, url, vendor, cat:string, assoc:seq[Assoc]) =
  for cos in os:
    let
      app = checkParam(findApp(cos, if app != "": app else: getCurrentDir()), "No Application." & cos.appx & " found under " & (if app != "": app else: getCurrentDir()))
      name = if name != "": name else:
        let fname = app.extractFilename
        fname.substr(0,fname.len - cos.appx.len-2)
      outdir = if outdir == "": getCurrentDir() else: outdir.absolutePath
      output_file = outdir / name.safe & "-" & version & "." & cos.packx
    outdir.createDir
    info "Creating " & ($cos).capitalizeAscii & " installer"
    case cos:
      of pMacos: createMacosPack(cos, os_template, output_file, app, name, res, noSign, entitlements)
      of pWin32, pWin64: createWindowsPack(cos, os_template, output_file, app, p12file, timestamp, res, name, version, descr, url, vendor, noSign, assoc)
      of pLinuxArm32, pLinuxArm64, pLinux64: createLinuxPack(cos, output_file, gpgdir, res, app, name, version, descr, cat, noSign)
      of pGeneric: createGenericPack(output_file, app)


