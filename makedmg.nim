import myexec, nim_miniz, tempfile, os, strutils, autos, sign

proc findDestination(dest,appname:string): string =
    var found:seq[string]
    for (kind,file) in dest.walkDir(relative=true):
        if kind == pcDir:
            if file==appname:
                echo "Found application " & appname
                return dest / file
            elif file.endsWith(".app"):
                found.add(file)
    kill("Unable to locate " & appname & ", found: " & join(found, ", "))

proc createDMGImpl(srcdmg, destdmg, app:string, sign:bool, entitlements:string)=
    # Define destination mount point
    let (_,randomname) = mkstemp("MakeApp-")
    randomname.deleteLater
    let volume = "/Volumes/" & randomname.extractFilename

    # Attach destination volume
    myexecQuiet "Detach old volume if any", "hdiutil detach " & volume
    myexec "Attach volume", "hdiutil attach -noautoopen -mountpoint " & volume & " " & srcdmg.quoteShell
    delegateLater(proc () =
        if volume.dirExists: myexec "Detach volume", "hdiutil detach -force " & volume
    )
    let appdest = findDestination(volume, app.extractFilename)

    appdest.removeDir
    appdest.createDir
    echo "Copy files"
    for file in app.walkDirRec(relative=true, yieldFilter={pcFile, pcDir}):
        let src = app / file
        let dest = appdest / file
        if src.dirExists:
            dest.createDir
        elif src.fileExists:
            copyFileWithPermissions src, dest
        else:
            kill("Unknown file at " & src)
    if sign:
        sign(appdest, entitlements)
    myexec "Detach volume", "hdiutil detach -force " & volume
    myexec "Compress volume", "hdiutil convert " & srcdmg.quoteShell & " -format UDZO -imagekey zlib-level=9 -ov -o " & destdmg.quoteShell
    if sign:
        sign(destdmg, entitlements)

proc createDMG*(zipdmg, destdmg, app:string, sign:bool, entitlements:string) =
    let tempdir = mkdtemp("notr_dmg_")
    tempdir.deleteLater
    echo "Unzip template"
    zipdmg.unzip(tempdir)
    for kind,path in tempdir.walkDir:
        if kind == pcFile and path.endsWith(".dmg"):
            createDMGImpl(path, destdmg, app, sign, entitlements)
            return
    kill("No DMG found in provided file")

   