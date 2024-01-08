import plists, argparse, sets, strutils, types
import sign, helper, myexec, package, autos, java

const VERSION {.strdefine.}: string = ""

template commonOutOpt() = option("-o", "--output", help="The output directory")
template commonOutImp(useCurrentDir=true) =
  let output {.inject.} = if opts.output == "": (if useCurrentDir: getCurrentDir() else:"") else: opts.output.absolutePath

template keyfileOpt() = option("--keyfile", help="The location of a configuration file that keys are stored.")
template keyfileImp() =
  let keyfile {.inject.} = opts.keyfile

template ostypeOpt() = option("--os", help="Comma separated list of possible operating system targets (defaults to \"system\", which is current system package): " & typesList())
template ostypeImp(single:bool) =
  let os {.inject.} = findOS(opts.os)
  if single and os.len>1: kill "Only one OS is supported for this mode"

template allOpt() =
  flag("-v", "--verbose", multiple=true, help="Be more verbose when signing files. 0=quiet and only errors, 1=show output, 2=show output and command, 3=show everything including passwords")
  flag("--keeponerror", help="Keep temporary files when commands fail to execute. This option is useful for debugging purposes")
template allImp() =
  VERBOCITY = opts.verbose
  KEEPONERROR = opts.keeponerror

template resOpt() = option("--res", help="The location of the resources files, needed when the application is built.")
template nameresImp() =
  let
    name {.inject.} = checkParam(opts.name.strip, "No application name provided")
    res {.inject.} = when compiles(opts.res): newResource(opts.res) else: newResource("")
    url {.inject.} = opts.url

template infoOpt(baseonly:bool) =
  option("--name", help="The name of the application")
  if not baseonly:
    option("--version", help="The version of the application")
    option("--descr", help="Application description")
    option("--cat", help="The categories of the application")
    option("--vendor", help="The vendor of the package")
    option("--assoc", multiple=true, help="File associations with this application. Format is EXT:MIMETYPE:DESCRIPTION. Only the EXT part is required. All other parts could be missing. To provide a custom icon, under resource folder use an file named as \"EXT.icns\". Usage example: \"ass:text/x-ssa:ASS Subtitle file\"")
  option("--url", help="Product URL")
template infoImp(res:Resource) =
  let
    version {.inject.} = if opts.version == "" : "1.0" else: opts.version
    descr {.inject.} = if opts.descr == "" : opts.name else: opts.descr
    assoc {.inject.} = findAccociations(opts.assoc, res)
    vendor {.inject.} = if opts.vendor == "": "Company" else: opts.vendor
    cat {.inject.} = opts.cat

template javaOpt() =
  option("--input", help="The input location of the application. If it is a file, it should be a JAR file. If it is a directory, all files in this directory are taken into consideration and the --jarname parameter should be provided")
  option("--jarname", help="If input is a directory, this parameter should define the JAR filename. Note: only the filename should be provided, not the relative or the absolute path.")
  resOpt()
  option("--extra", help="The location of extra files to added to the bundle. This is a hierarchical folder, where first level has the name of the target (as defined by system target) or special keywords \"windows\" for all Windows targets and \"common\" for all targets. Second level are all files that will be merged with the files located at appdir.")
  option("--jvmopt", multiple=true, help="JVM option. Could be used more than once.") # -Dawt.useSystemAAFontSettings=on -Dswing.aatext=true
  option("--id", help="Reverse URL unique identifier")
  option("--jdk", help="The location of the JDK")
template javaImp(name:string) =
  let
    input {.inject.} = opts.input.absolutePath.normalizedPath
    jarname {.inject.} = if input.dirExists:
        let cjar = opts.jarname
        if cjar == "" : kill "Parameter --jarname is mandatory, if --input is a directory"
        if cjar.contains(DirSep): kill "Parameter --jarname should not contain a path"
        if not (input/cjar).fileExists: kill "Unable to locate JAR " & (input/cjar)
        cjar
      elif input.fileExists:
        if opts.jarname != "": kill "Parameter --input provided a file; it is not allowed to use --jarname"
        input.extractFilename
      else:
        kill "Unknown input: " & opts.input
        ""
    extra {.inject.} = opts.extra
    jvmopts {.inject.} = getJvmOpts(opts.jvmopt)
    id {.inject.} = if opts.id == "": constructId(url, vendor, name) else: opts.id
    jdk {.inject.} = opts.jdk
  if not jarname.toLowerAscii.endsWith(".jar"):
    kill "JAR file should end with \".jar\" extension, given: " & jarname

template noSignOpt() =
  option("--nosign", help="Comma separated list of possible operating system targets that should not be signed. See --os option.")
template noSignImp =
  let noSign {.inject.} = findOS(opts.nosign)

template signOpt() =
  option("--p12file", help="🍏 The p12 file containing the signing keys.")
  option("--p12pass", help="🍏 The file containing the password of the p12file.")
  option("--notary", help="🍏 Use the provided file as notary JSON.")
  option("--wincert", help="🪟 Use the provided certificate.")
  option("--winidfile", help="🪟 The file containing the signing token ID.")
  option("--winpinfile", help="🪟 The file containing the signing pin.")
template signImp(keyfile:string) =
  P12FILE = opts.p12file
  P12PASS = opts.p12pass
  NOTARY = opts.notary
  WINCERT = opts.wincert
  for t in os:
    if not noSign.contains(t):
      if t == pMacos:
        if P12FILE == "": kill "No p12 file provided"
        elif not P12FILE.fileExists: kill "No p12 file " & P12FILE & " exists"
        if P12PASS == "": kill "No p12 file password provided"
        elif not P12PASS.fileExists: kill "No p12 file password " & P12PASS & " exists"
        if NOTARY == "": kill "No notary JSON file provided"
        elif not NOTARY.fileExists: kill "No notary JSON file " & NOTARY & " exists"
      if t in windowsTargets:
        if WINCERT == "": kill "No Windows certificate file provided"
        elif not WINCERT.fileExists: kill "No Windows certificate file " & WINCERT & " exists"
        elif not WINCERT.endsWith(".pem"): kill "Only *.pem files are supported to sign Windows executables"
        WINID = readContent(opts.winidfile, "signing token ID")
        WINPIN = readContent(opts.winpinfile, "signing pin")

const p = newParser("makeapp"):
  help("makeapp " & VERSION & "\n\nCreate, sign, and notarize DMG files for the Apple store, to make later versions of macOS happy.\nMore info at https://github.com/teras/makeapp")
  command("help"):
    run:
      echo """
Environmental variables:
  macOS:
    NOTARIZE_APP_PASSWORD : The notarizing password of the current user
    NOTARIZE_USER         : The notarizing user
    NOTARIZE_ASC_PROVIDER : Notarizing asc. provider
    NOTARIZE_SIGN_ID      : The ID of the user which will be used to sing the application 
  Windows:
    SIGN_P12_PASS         : The password of the p12 file
  Linux:
    GPG_KEY               : The password of the GnuPG file

Default resources:
  All targets:
    app.png          : The application icon
    [ASSOC].png      : The file association icons for file extensions ASSOC. E.g. for an association of ".txt" files, the filename should be "txt.png"
  
  macOS specific: 
    app.icns         : The application icon
    dmg_template.zip : The application DMG template
    [ASSOC].icns     : The file association icons for file extensions ASSOC. E.g. for an association of ".txt" files, the filename should be "txt.icns"

  Windows specific:
    app.ico          : The application icon
    install.ico      : The installer icon
    logo-install.bmp : The logo to display on the left of the installer
    logo-install-small.bmp
    logo-install-small.bmp
                     : The small icon to display on the installer
    [ASSOC].ico      : The file association icons for file extensions ASSOC. E.g. for an association of ".txt" files, the filename should be "txt.ico"

  Linux specific:
    app.png          : The application icon

Extras folder organization:
    extras
    ├── common
    ├── linux32
    ├── linux64
    ├── linux
    ├── win32
    ├── win64
    ├── windows
    └── macos
     
      """
      exit(true)
  command("java"):
    commonOutOpt()
    infoOpt(false)
    javaOpt()
    ostypeOpt()
    allOpt()
    run:
      commonOutImp()
      nameresImp()
      infoImp(res)
      javaImp(name)
      ostypeImp(false)
      allImp()
      safedo: makeJava(os, output, res, name, version, input, jarname, jvmopts, assoc, extra, vendor, descr, id, url, jdk)
      exit()
  command("pack"):
    commonOutOpt()
    infoOpt(false)
    resOpt()
    ostypeOpt()
    noSignOpt()
    signOpt()
    option("--templ", help="The location of the template (e.g. DMG under macOS, Inno setup under Windows)")
    option("--target", help="The location of the application. When missing the system will try to scan the directory tree below this point")
    keyfileOpt()
    allOpt()
    run:
      commonOutImp(false)
      nameresImp()
      infoImp(res)
      keyfileImp()
      let templ = checkParam(opts.templ, "No template found", asFile=true)
      ostypeImp(true)
      noSignImp()
      signImp(keyfile)
      allImp()
      safedo: createPack(os, templ, output, opts.target, noSign, res, name, version, descr, url, vendor, cat, assoc)
      exit()
  command("sign"):
    option("-t", "--target", help="The location of the target file (DMG or Application.app). When missing the system will scan the directory tree below this point")
    ostypeOpt()
    noSignOpt()
    signOpt()
    infoOpt(true)
    keyfileOpt()
    allOpt()
    run:
      keyfileImp()
      ostypeImp(true)
      nameresImp()
      noSignImp()
      signImp(keyfile)
      allImp()
      safedo: signApp(os, opts.target, name)
      exit()
  command("create"):
    commonOutOpt()
    infoOpt(false)
    javaOpt()
    option("--instoutput", help="The output location of the installer files. Defaults to the same as --output")
    ostypeOpt()
    noSignOpt()
    signOpt()
    keyfileOpt()
    allOpt()
    run:
      commonOutImp()
      nameresImp()
      infoImp(res)
      javaImp(name)
      keyfileImp()
      ostypeImp(false)
      noSignImp()
      signImp(keyfile)
      let instoutput = if opts.instoutput == "": output else: opts.instoutput
      allImp()
      safedo: makeJava(os, output, res, name, version, input, jarname, jvmopts, assoc, extra, vendor, descr, id, url, jdk)
      safedo: createPack(os, "", instoutput, output, noSign, res, name, version, descr, url, vendor, cat, assoc)
      exit()
p.run(commandLineParams())
stdout.write(p.help)
kill("No options given")
