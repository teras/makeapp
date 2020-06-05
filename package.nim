import myexec, nim_miniz, os, strutils, autos, sign, helper, types

proc findDestination(dest,appname:string): string =
  var found:seq[string]
  for (kind,file) in dest.walkDir(relative=true):
    if kind == pcDir:
      if file==appname:
        info "Found application " & appname
        return dest / file
      elif file.endsWith(".app"):
        found.add(file)
  kill("Unable to locate application \"" & appname & "\", found: " & join(found, ", "))

proc createDMGImpl(srcdmg, output_file, app:string, sign:bool, entitlements:string)=
  # Define destination mount point
  let volume = "/Volumes/" & randomFile().extractFilename

  # Attach destination volume
  myexecQuiet "Detach old volume if any", "hdiutil", "detach", volume
  myexec "Attach volume", "hdiutil", "attach", "-noautoopen", "-mountpoint", volume, srcdmg
  delegateLater(proc () =
    if volume.dirExists: myexec "Detach volume", "hdiutil", "detach", "-force", volume
  )
  let appdest = findDestination(volume, app.extractFilename)
  appdest.removeDir
  appdest.createDir
  info "Copy files"
  merge appdest, app
  if sign:
    sign(@[pMacos], appdest, entitlements)
  myexec "Detach volume", "hdiutil", "detach", "-force", volume
  myexec "Compress volume", "hdiutil", "convert", srcdmg, "-format", "UDZO", "-imagekey", "zlib-level=9", "-ov", "-o", output_file
  if sign:
    sign(@[pMacos], output_file, entitlements)

proc createPack*(os:seq[OSType], dmg_template, output_file, app:string, sign:bool, entitlements, name, version, descr, url:string) =
  for cos in os:
    let app = checkParam(findApp(cos, if app != "": app else: getCurrentDir()), "No [Application]." & cos.appx & " found under " & (if app != "": app else: getCurrentDir()))
    let output_file = if output_file == "":
        let fname = app.extractFilename
        fname.substr(0,fname.len-5) & ".dmg"
      elif output_file.endsWith(".dmg"): output_file
      else: output_file & ".dmg"
    let tempdir = randomDir()
    info "Unzip template"
    dmg_template.unzip(tempdir)
    for kind,path in tempdir.walkDir:
      if kind == pcFile and path.endsWith(".dmg"):
        createDMGImpl(path, output_file, app, sign, entitlements)
        return
    kill("No DMG found in provided file")

   
