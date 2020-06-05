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
  option("--os", help="Comma separated list of possible operating system targets: " & OSType.mapIt($it).join(", "))
  option("--res", help="The location of the resources files, that are static for all pachages, e.g. icons.")
  option("--name", help="The name of the application")
  option("--applib", help="The directory where the application itself is stored")
  option("--jar", help="The desired entry JAR")
  option("--modules", help="Comma separated list of required modules. Defaults to \"java.datatransfer,java.desktop,java.logging,java.prefs,java.rmi,java.xml,jdk.charsets\"")
  option("--jvmopt", multiple=true, help="JVM option. Could be used more than once. If DEFAULTS are given, then the options \"-Dawt.useSystemAAFontSettings=on\" and \"-Dswing.aatext=true\" are added")
  option("--id", help="Reverse URL unique identifier")
  option("--descr", help="Application description")
  option("--assoc", multiple=true, help="File associations with this application. Format is EXT:DESCRIPTION:MIMETYPE:ICONNAME. Only the EXT part is required. All other parts could be missing. For example \"ass:ASS Subtitle file:text/x-ssa:subtitle\"")
  option("--icon", help="The application icon name resource")
  option("--splash", help="The application splash resource")
  option("--version", help="The version of the application")
  option("--vendor", help="The vendor of the package")
  option("--url", help="Product URL")
  option("--jdk", help="The location of the JDK")
template javaImp() =
  let
    username {.inject.} = findUsername()
    os {.inject.} = findOS(opts.os)
    res {.inject.} = if opts.res == "": "" else: checkParam(opts.res, "Unable to locate directory " & opts.res, asDir=true)
    name {.inject.} = checkParam(opts.name.strip, "No application name provided")
    applib {.inject.} = checkParam(opts.applib, "No application directory provided", asDir=true).absolutePath.normalizedPath
    jar {.inject.} = getJar(opts.jar, applib)
    modules {.inject.} = if opts.modules == "" : "java.datatransfer,java.desktop,java.logging,java.prefs,java.rmi,java.xml,jdk.charsets" else: opts.modules
    jvmopts {.inject.} = getJvmOpts(opts.jvmopt)
    id {.inject.} = if opts.id == "": constructId(username, name) else: opts.id
    descr {.inject.} = if opts.descr == "" : opts.name else: opts.descr
    assoc {.inject.} = findAccociations(opts.assoc)
    icon {.inject.} = opts.icon
    splash {.inject.} = opts.splash
    version {.inject.} = if opts.version == "" : "1.0" else: opts.version
    vendor {.inject.} = if opts.vendor == "": username.capitalizeAscii else: opts.vendor
    url {.inject.} = opts.url
    jdk {.inject.} = opts.jdk

template signOpt() =
  option("--signid", help="The sign id, as given by `security find-identity -v -p codesigning`")
  option("--entitle", help="Use the provided file as entitlements, defaults to a generic entitlements file")
template signImp(sign:bool, keyfile:string) =
  if sign:
    let config = if keyfile != "" and keyfile.fileExists: loadConfig(keyfile) else: newConfig()
    ID = checkParam(if opts.signid != "" : opts.signid else: getEnv(NOTARIZE_SIGN_ID, config.getSectionValue("", NOTARIZE_SIGN_ID)), "No sign id provided")
  let entitle {.inject.} = if not sign: "" else: checkParam(if opts.entitle == "": getDefaultEntitlementFile() else: opts.entitle.absolutePath.normalizedPath, "Required entitlements file " & opts.entitle & " does not exist")

template createOpt() =
  option("--dmg", help="The location of the DMG template")
  signOpt()
template createImp(sign:bool, keyfile:string) =
  signImp(sign, keyfile)
  let dmg {.inject.} = checkParam(opts.dmg, "No DMG template found", asFile=true)

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
      echo "Some help info"
      exit(true)
  command("create"):
    commonOutOpt()
    javaOpt()
    createOpt()
    option("--notarize", help="Notarize DMG application after creation, boolean value. Defaults to false")
    sendOpt()
    verboseOpt()
    run:
      commonOutImp()
      javaImp()
      createImp(true, opts.parentOpts.keyfile)
      let notarize = opts.notarize.isTrue
      sendImp(notarize)
      verboseImp()
      safedo: makeJava(os, output, res, name, version, applib, jar, modules, jvmopts, assoc, icon, splash, vendor, descr, id, url, jdk)
      let appOut = output / name & ".app"
      let dmgOut = output / name & "-" & version & ".dmg"
      safedo: createDMG(dmg, dmgOut, appOut, true, entitle)
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
      safedo: makeJava(os, output, res, name, version, applib, jar, modules, jvmopts, assoc, icon, splash, vendor, descr, id, url, jdk)
      exit()
  command("dmg"):
    commonOutOpt()
    createOpt()
    option("--target", help="The location of the target file (Application.app). When missing the system will scan the directory tree below this point")
    flag("--nosign", help="Skp sign procedure")
    verboseOpt()
    run:
      commonOutImp(false)
      let sign = not opts.nosign
      createImp(sign, opts.parentOpts.keyfile)
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
