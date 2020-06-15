import myexec, nim_miniz, os, strutils, autos, sign, helper, types, sequtils, strformat

const BACKGROUND_DMG = when system.hostOS == "macosx": "background.jpg".readFile else:""

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

proc createDMGImpl(givenDmg, output_file, app, name:string, sign:bool, entitlements:string)=
  # Define destination mount point
  let volume = "/Volumes/" & randomFile().extractFilename
  let isDmgCustom = not givenDmg.fileExists
  let srcdmg = if isDmgCustom: randomFile() & ".dmg" else: givenDmg

  # Attach destination volume
  myexecQuiet "Detach old volume if any", "hdiutil", "detach", volume
  if isDmgCustom:
    myexec "Create new DMG file", "hdiutil", "create", "-volname", name, "-fs", "HFS+", "-size", "100M" , "-srcfolder", app, "-fsargs", "-c c=64,a=16,e=16", "-format", "UDRW", srcdmg
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
  if sign:
    sign(@[pMacos], appdest, entitlements, "", "", "")
  myexec "Detach volume", "hdiutil", "detach", "-force", volume
  myexec "Compress volume", "hdiutil", "convert", srcdmg, "-format", "UDZO", "-imagekey", "zlib-level=9", "-ov", "-o", output_file
  if sign:
    sign(@[pMacos], output_file, entitlements, "", "", "")

proc createMacosPack(dmg_template, output_file, app, name:string, res:Resource, sign:bool, entitlements: string) =
  let dmg_template = if dmg_template=="": res.path("dmg_template.zip") else:dmg_template
  if dmg_template!="":
    let tempdir = randomDir()
    info "Unzip template"
    dmg_template.unzip(tempdir)
    for kind,path in tempdir.walkDir:
      if kind == pcFile and path.endsWith(".dmg"):
        createDMGImpl(path, output_file, app, name, sign, entitlements)
        return
    kill("No DMG found in provided file")
  else: createDMGImpl("", output_file, app, name, sign, entitlements)

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

proc createWindowsPack(os:OSType, os_template, output_file, app, p12file:string, res:Resource, name, version, descr, url, vendor:string, sign:bool, associations:seq[Assoc]) =
  let inst_res = randomDir()
  let issContent = if os_template=="": constructISS(os, app, res, inst_res, name, version, url, vendor, associations) else: readFile(os_template)
  writeFile(inst_res / "installer.iss", issContent)
  myexec "", "docker", "run", "--rm", "-v", inst_res&":/work", "-v", app&":/work/app", "amake/innosetup", "installer.iss"
  moveFile inst_res / name & ".exe", output_file
  if sign:
    sign(@[os], output_file, "", p12file, name, url)

proc createLinuxPack(os:OSType, output_file, gpgdir:string, res:Resource, app, name, descr, cat:string, sign:bool) =
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
  let runtime = if os==pLinuxArm32 or os==pLinuxArm64: "--runtime-file /opt/appimage/runtime-" & os.cpu else:""
  let signcmd = if not sign: "" else: "gpg-agent --daemon; gpg2 --detach-sign --armor --pinentry-mode loopback --passphrase '" & GPGPASS & "' `mktemp` ; "
  myexec "", "docker", "run", "-t", "--rm", "-v", gpgdir&":/root/.gnupg", "-v", inst_res&":/usr/src/app", "-v", app&":/usr/src/app/" & cname, "crossmob/appimage-builder", "bash", "-c", 
    signcmd & "/opt/appimage/AppRun --comp xz " & runtime & " -v " & cname & (if sign:" --sign" else:"") & " -n " & name.safe & ".appimage"
  moveFile inst_res / name.safe & ".appimage", output_file

proc createGenericPack(output_file, app:string) =
  myexec "", "tar", "jcvf", output_file, "-C", app.parentDir, app.extractFilename

proc createPack*(os:seq[OSType], os_template:string, outdir, app:string, sign:bool, entitlements, p12file, gpgdir:string, res:Resource, name, version, descr, url, vendor, cat:string, assoc:seq[Assoc]) =
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
      of pMacos: createMacosPack(os_template, output_file, app, name, res, sign, entitlements)
      of pWin32, pWin64: createWindowsPack(cos, os_template, output_file, app, p12file, res, name, version, descr, url, vendor, sign, assoc)
      of pLinuxArm32, pLinuxArm64, pLinux64: createLinuxPack(cos, output_file, gpgdir, res, app, name, descr, cat, sign)
      of pGeneric: createGenericPack(output_file, app)
    
    

   
