import parsecfg, plists, argparse, sets
import sendtoapple, sign, helper, myexec, makedmg, autos

const NOTARIZE_APP_PASSWORD = "NOTARIZE_APP_PASSWORD"
const NOTARIZE_USER     = "NOTARIZE_USER"
const NOTARIZE_ASC_PROVIDER = "NOTARIZE_ASC_PROVIDER"
const NOTARIZE_SIGN_ID      = "NOTARIZE_SIGN_ID"

const VERSION {.strdefine.}: string = ""

proc storeID(given:string, keyfile:string) =
  let config = if keyfile != "" and keyfile.fileExists: loadConfig(keyfile) else: newConfig()
  ID = if given != "" : given else: getEnv(NOTARIZE_SIGN_ID, config.getSectionValue("", NOTARIZE_SIGN_ID))
  if ID == "": kill("No sign id provided")

proc getEntitlements(given:string): string=
  result = if given == "": getDefaultEntitlementFile() else: given.absolutePath.normalizedPath
  if not result.fileExists: kill("Required entitlements file " & given & " does not exist")


const p = newParser("makeapp " & VERSION):
  help("Create, sign, and notarize DMG files for the Apple store, to make later versions of macOS happy.\nMore info at https://github.com/teras/makeapp")
  option("-k", "--keyfile", help="The location of a configuration file that keys are stored.")
  command("create"):
    option("-s", "--source", help="The location of the DMG template")
    option("-o", "--output", help="The output DMG file")
    option("-t", "--target", help="The location of the target file (Application.app). When missing the system will scan the directory tree below this point")
    option("-n", "--name", help="The name of the application")
    flag("-k", "--nosign", help="Skp sign procedure")
    option("-i", "--signid", help="The sign id, as given by `security find-identity -v -p codesigning`")
    option("-e", "--entitlements", help="Use the provided file as entitlements, defaults to a generic entitlements file")
    flag("-v", "--verbose", multiple=true, help="Be more verbose when signing files. 0=quiet and only errors, 1=show output, 2=show output and command, 3=show everything including passwords")
    run:
      VERBOCITY = opts.verbose
      let target = findApp(if opts.target != "": opts.target else: getCurrentDir())
      if target == "": kill("No [Application].app found under " & target)
      if not opts.source.fileExists: kill("No DMG template found")
      if opts.output == "": kill("No ouput defined")
      var entitlements:string
      if not opts.nosign:
        storeID(opts.signid, opts.parentOpts.keyfile)
        entitlements = getEntitlements(opts.entitlements)
      createDMG(opts.source, opts.output, target, not opts.nosign, entitlements)
      exit()
  command("sign"):
    option("-t", "--target", help="The location of the target file (DMG or Application.app). When missing the system will scan the directory tree below this point")
    option("-i", "--signid", help="The sign id, as given by `security find-identity -v -p codesigning`")
    option("-e", "--entitlements", help="Use the provided file as entitlements, defaults to a generic entitlements file")
    flag("-v", "--verbose", multiple=true, help="Be more verbose when signing files. 0=quiet and only errors, 1=show output, 2=show output and command, 3=show everything including passwords")
    run:
      VERBOCITY = opts.verbose
      storeID(opts.signid, opts.parentOpts.keyfile)
      var target = findApp(if opts.target != "": opts.target else: getCurrentDir())
      if target == "": target = findDmg(if opts.target != "": opts.target else: getCurrentDir())
      if target == "": kill("No target file provided")
      let entitlements = getEntitlements(opts.entitlements)
      sign(target, entitlements)
      exit()
  command("send"):
    option("-t", "--target", help="The location of the DMG/ZIP file. When missing the system will scan the directory tree below this point")
    option("-b", "--bundleid", help="The required BundleID. When missing, the system guess from existing PList files inside an .app folder")
    option("-p", "--password", help="The Apple password")
    option("-u", "--user", help="The Apple username")
    option("-a", "--ascprovider", help="The specific associated provider for the current Apple developer account")
    flag("-q", "--shouldask", help="When run in a script, ask for confirmation first")
    flag("-v", "--verbose", multiple=true, help="Be more verbose when signing files. 0=quiet and only errors, 1=show output, 2=show output and command, 3=show everything including passwords")
    run:
      VERBOCITY = opts.verbose
      let config = if opts.parentOpts.keyfile != "" and opts.parentOpts.keyfile.fileExists: loadConfig(opts.parentOpts.keyfile) else: newConfig()
      PASSWORD = if opts.password != "": opts.password else: getEnv(NOTARIZE_APP_PASSWORD, config.getSectionValue("",NOTARIZE_APP_PASSWORD))
      if PASSWORD == "": kill("No password provided")
      USER = if opts.user != "": opts.user else: getEnv(NOTARIZE_USER, config.getSectionValue("", NOTARIZE_USER))
      if USER == "": kill("No user provided")
      let ctarget = if opts.target != "": opts.target else: getCurrentDir()
      let plist = findPlist(ctarget)
      let bundleId = if opts.bundleid != "": opts.bundleid else: loadPlist(plist).getOrDefault("CFBundleIdentifier").getStr("")
      if bundleId == "": kill("No Bundle ID provided")
      var fileToSend = findDmg(ctarget)
      if fileToSend == "": fileToSend = findZip(ctarget)
      if fileToSend == "":kill("No target file found")
      let asc_provider = if opts.ascprovider != "": opts.ascprovider else: getEnv(NOTARIZE_ASC_PROVIDER, config.getSectionValue("", NOTARIZE_ASC_PROVIDER))
      sendToApple(bundleId, fileToSend, asc_provider, opts.shouldask)
      exit()
p.run(commandLineParams())
stdout.write(p.help)
kill("No options given")
