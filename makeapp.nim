import parsecfg, plists, argparse, sets, strutils, sequtils
import sendtoapple, sign, helper, myexec, makedmg, autos, java

const NOTARIZE_APP_PASSWORD = "NOTARIZE_APP_PASSWORD"
const NOTARIZE_USER         = "NOTARIZE_USER"
const NOTARIZE_ASC_PROVIDER = "NOTARIZE_ASC_PROVIDER"
const NOTARIZE_SIGN_ID      = "NOTARIZE_SIGN_ID"

const VERSION {.strdefine.}: string = ""

template commonOutOpt() = option("-o", "--output", help="The output directory")
template commonOutImp(useCurrentDir=true) =
  let output {.inject.} = if opts.output == "": (if useCurrentDir: getCurrentDir() else:"") else: opts.output.absolutePath

template verboseOpt() = flag("-v", "--verbose", multiple=true, help="Be more verbose when signing files. 0=quiet and only errors, 1=show output, 2=show output and command, 3=show everything including passwords")
template verboseImp() =
  VERBOCITY = opts.verbose

template javaOpt() =
  option("--name", help="The name of the application")
  option("--applib", help="The directory where the application itself is stored")
  option("--jar", help="The desired entry JAR")
  option("--res", help="The location of the resources files, needed when the application is built.")
  option("--extra", help="The location of extra files to added to the bundle. This is a hierarchical folder, where first level has the name of the target (as defined by system target) or special keywords \"windows\" for all Windows targets and \"common\" for all targets. Second level are all files that will be merged with the files located at applib.")
  option("--modules", help="Comma separated list of required modules. Defaults to \"java.datatransfer,java.desktop,java.logging,java.prefs,java.rmi,java.xml,jdk.charsets\"")
  option("--jvmopt", multiple=true, help="JVM option. Could be used more than once. If DEFAULTS are given, then the options \"-Dawt.useSystemAAFontSettings=on\" and \"-Dswing.aatext=true\" are added")
  option("--id", help="Reverse URL unique identifier")
  option("--descr", help="Application description")
  option("--assoc", multiple=true, help="File associations with this application. Format is EXT:MIMETYPE:DESCRIPTION. Only the EXT part is required. All other parts could be missing. To provide a custom icon, under resource folder use an file named as \"EXT.icns\". Usage example: \"ass:text/x-ssa:ASS Subtitle file\"")
  option("--version", help="The version of the application")
  option("--vendor", help="The vendor of the package")
  option("--url", help="Product URL")
  option("--jdk", help="The location of the JDK")
  option("--os", help="Comma separated list of possible operating system targets (defaults to \"system\", which is current system package): " & typesList())
template javaImp() =
  let username = findUsername() # Used in current context only
  let
    name {.inject.} = checkParam(opts.name.strip, "No application name provided")
    applib {.inject.} = checkParam(opts.applib, "No application directory provided", asDir=true).absolutePath.normalizedPath
    jar {.inject.} = getJar(opts.jar, applib)
    res {.inject.} = if opts.res == "": "" else: checkParam(opts.res, "Unable to locate directory " & opts.res, asDir=true)
    extra {.inject.} = opts.extra
    modules {.inject.} = if opts.modules == "" : "java.datatransfer,java.desktop,java.logging,java.prefs,java.rmi,java.xml,jdk.charsets" else: opts.modules
    jvmopts {.inject.} = getJvmOpts(opts.jvmopt)
    id {.inject.} = if opts.id == "": constructId(username, name) else: opts.id
    descr {.inject.} = if opts.descr == "" : opts.name else: opts.descr
    assoc {.inject.} = findAccociations(opts.assoc, res)
    version {.inject.} = if opts.version == "" : "1.0" else: opts.version
    vendor {.inject.} = if opts.vendor == "": username.capitalizeAscii else: opts.vendor
    url {.inject.} = opts.url
    jdk {.inject.} = opts.jdk
    os {.inject.} = findOS(opts.os)

template signOpt() =
  option("--signid", help="The sign id, as given by `security find-identity -v -p codesigning`")
  option("--entitle", help="Use the provided file as entitlements, defaults to a generic entitlements file")
template signImp(sign:bool, keyfile:string) =
  if sign:
    let config = if keyfile != "" and keyfile.fileExists: loadConfig(keyfile) else: newConfig()
    ID = checkParam(if opts.signid != "" : opts.signid else: getEnv(NOTARIZE_SIGN_ID, config.getSectionValue("", NOTARIZE_SIGN_ID)), "No sign id provided")
  let entitle {.inject.} = if not sign: "" else: checkParam(if opts.entitle == "": getDefaultEntitlementFile() else: opts.entitle.absolutePath.normalizedPath, "Required entitlements file " & opts.entitle & " does not exist")


template sendOpt() =
  option("--password", help="The Apple password")
  option("--user", help="The Apple username")
  option("--ascprovider", help="The specific associated provider for the current Apple developer account")
template sendImp(strict:bool) =
  let config = if opts.parentOpts.keyfile != "" and opts.parentOpts.keyfile.fileExists: loadConfig(opts.parentOpts.keyfile) else: newConfig()
  let
    ascprovider {.inject.} = if opts.ascprovider != "": opts.ascprovider else: getEnv(NOTARIZE_ASC_PROVIDER, config.getSectionValue("", NOTARIZE_ASC_PROVIDER))
  PASSWORD = if opts.password != "": opts.password else: getEnv(NOTARIZE_APP_PASSWORD, config.getSectionValue("",NOTARIZE_APP_PASSWORD))
  USER = if opts.user != "": opts.user else: getEnv(NOTARIZE_USER, config.getSectionValue("", NOTARIZE_USER))
  if strict:
    checkParam PASSWORD, "No password provided"
    checkParam USER, "No user provided"


const p = newParser("makeapp " & VERSION):
  help("Create, sign, and notarize DMG files for the Apple store, to make later versions of macOS happy.\nMore info at https://github.com/teras/makeapp")
  option("-k", "--keyfile", help="The location of a configuration file that keys are stored.")
  command("help"):
    run:
      echo """
Default resources:
  macOS specific: 
    app.icns         : The application icon
    dmg_template.zip : The application DMG template
    [ASSOC].icns       : The file association icons for file extensions ASSOC. E.g. for an association of ".txt" files, the filename should be "txt.icns"
      """
      exit(true)
  command("create"):
    commonOutOpt()
    javaOpt()
    option("--notarize", help="Notarize DMG application after creation, boolean value. Defaults to false")
    signOpt()
    sendOpt()
    verboseOpt()
    run:
      commonOutImp()
      javaImp()
      signImp(true, opts.parentOpts.keyfile)
      let notarize = opts.notarize.isTrue
      sendImp(notarize)
      verboseImp()
      safedo: makeJava(os, output, res, name, version, applib, jar, modules, jvmopts, assoc, extra, vendor, descr, id, url, jdk)
      let appOut = output / name & ".app"
      let dmgIn = checkParam(res.resource("dmg_template.zip"), "No " & res / "dmg_template.zip DMG template found")
      let dmgOut = output / name & "-" & version & ".dmg"
      safedo: createDMG(dmgIn, dmgOut, appOut, true, entitle)
      if notarize:
        safedo: sendToApple(id, dmgOut, ascprovider)
      exit()
  command("java"):
    commonOutOpt()
    javaOpt()
    verboseOpt()
    run:
      commonOutImp()
      javaImp()
      verboseImp()
      safedo: makeJava(os, output, res, name, version, applib, jar, modules, jvmopts, assoc, extra, vendor, descr, id, url, jdk)
      exit()
  command("dmg"):
    commonOutOpt()
    signOpt()
    option("--dmg", help="The location of the DMG template")
    option("--target", help="The location of the target file (Application.app). When missing the system will scan the directory tree below this point")
    flag("--nosign", help="Skp sign procedure")
    verboseOpt()
    run:
      commonOutImp(false)
      let dmg {.inject.} = checkParam(opts.dmg, "No DMG template found", asFile=true)
      let sign = not opts.nosign
      signImp(sign, opts.parentOpts.keyfile)
      verboseImp()
      safedo: createDMG(dmg, output, opts.target, sign, entitle)
      exit()
  command("sign"):
    option("-t", "--target", help="The location of the target file (DMG or Application.app). When missing the system will scan the directory tree below this point")
    signOpt()
    verboseOpt()
    run:
      signImp(true, opts.parentOpts.keyfile)
      verboseImp()
      var target = findApp(if opts.target != "": opts.target else: getCurrentDir())
      if target == "": target = findDmg(if opts.target != "": opts.target else: getCurrentDir())
      if target == "": kill("No target file provided")
      safedo: sign(target, entitle)
      exit()
  command("notarize"):
    sendOpt()
    option("--id", help="Reverse URL unique identifier. When missing, the system guess from existing PList files inside an .app folder")
    option("-t", "--target", help="The location of the DMG/ZIP file. When missing the system will scan the directory tree below this point")
    verboseOpt()
    run:
      sendImp(true)
      verboseImp()
      let target = if opts.target != "": opts.target else: getCurrentDir()
      let id = checkParam(if opts.id != "": opts.id else: loadPlist(findPlist(target)).getOrDefault("CFBundleIdentifier").getStr(""), "No Bundle ID provided")
      var fileToSend = findDmg(target)
      if fileToSend == "": fileToSend = findZip(target)
      if fileToSend == "":kill("No target file found")
      safedo: sendToApple(id, fileToSend, ascprovider)
      exit()
p.run(commandLineParams())
stdout.write(p.help)
kill("No options given")
