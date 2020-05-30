import parsecfg, plists, argparse, sets
import sendtoapple, sign, helper, myexec

const NOTARIZE_APP_PASSWORD = "NOTARIZE_APP_PASSWORD"
const NOTARIZE_USER         = "NOTARIZE_USER"
const NOTARIZE_ASC_PROVIDER = "NOTARIZE_ASC_PROVIDER"
const NOTARIZE_SIGN_ID      = "NOTARIZE_SIGN_ID"

const VERSION {.strdefine.}: string = ""

const p = newParser("makeapp " & VERSION):
    help("Sign, create and notarize DMG files for the Apple store, to make later versions of macOS happy. For more info check https://github.com/teras/makeapp")
    option("-k", "--keyfile", help="The location of a configuration file that keys are stored.")
    command("sign"):
        option("-t", "--target", help="The location of the target file (DMG or Application.app). When missing the system will scan the directory tree below this point")
        option("-i", "--signid", help="The sign id, as given by `security find-identity -v -p codesigning`")
        option("-e", "--entitlements", help="Use the provided file as entitlements, defaults to a generic entitlements file")
        flag("-v", "--verbose", multiple=true, help="Be more verbose when signing files. 0=quiet and only errors, 1=show output, 2=show output and command, 3=show everything including passwords")
        run:
            VERBOCITY = opts.verbose
            let config = if opts.parentOpts.keyfile != "" and opts.parentOpts.keyfile.fileExists: loadConfig(opts.parentOpts.keyfile) else: newConfig()
            ID = if opts.signid != "" : opts.signid else: getEnv(NOTARIZE_SIGN_ID, config.getSectionValue("", NOTARIZE_SIGN_ID))
            if ID == "": quit("No sign id provided")
            var target = findApp(if opts.target != "": opts.target else: getCurrentDir())
            if target == "": target = findDmg(if opts.target != "": opts.target else: getCurrentDir())
            if target == "": quit("No target file provided")
            ENTITLEMENTS = if opts.entitlements == "": getDefaultEntitlementFile() else: opts.entitlements.absolutePath.normalizedPath
            if not ENTITLEMENTS.fileExists: quit("Required entitlemens file " & opts.entitlements & " does not exist")
            sign(target)
            exit()
    command("send"):
        option("-t", "--target", help="The location of the DMG file. When missing the system will scan the directory tree below this point")
        option("-b", "--bundleid", help="The required BundleID. When missing, the system guess from existing PList files inside an .app folder")
        option("-p", "--password", help="The Apple password")
        option("-u", "--user", help="The Apple username")
        option("-a", "--ascprovider", help="The specific associated provider for the current Apple developer account")
        flag("-y", "--yes", help="When run in a script, skip asking for confirmation")
        flag("-v", "--verbose", multiple=true, help="Be more verbose when signing files. 0=quiet and only errors, 1=show output, 2=show output and command, 3=show everything including passwords")
        run:
            VERBOCITY = opts.verbose
            let config = if opts.parentOpts.keyfile != "" and opts.parentOpts.keyfile.fileExists: loadConfig(opts.parentOpts.keyfile) else: newConfig()
            PASSWORD = if opts.password != "": opts.password else: getEnv(NOTARIZE_APP_PASSWORD, config.getSectionValue("",NOTARIZE_APP_PASSWORD))
            if PASSWORD == "": quit("No password provided")
            USER = if opts.user != "": opts.user else: getEnv(NOTARIZE_USER, config.getSectionValue("", NOTARIZE_USER))
            if USER == "": quit("No user provided")
            let ctarget = if opts.target != "": opts.target else: getCurrentDir()
            let plist = findPlist(ctarget)
            let bundleId = if opts.bundleid != "": opts.bundleid else: loadPlist(plist).getOrDefault("CFBundleIdentifier").getStr("")
            if bundleId == "": quit("No Bundle ID provided")
            var fileToSend = findDmg(ctarget)
            if fileToSend == "": fileToSend = findZip(ctarget)
            if fileToSend == "":quit("No target file found")
            let asc_provider = if opts.ascprovider != "": opts.ascprovider else: getEnv(NOTARIZE_ASC_PROVIDER, config.getSectionValue("", NOTARIZE_ASC_PROVIDER))
            sendToApple(bundleId, fileToSend, asc_provider, not opts.yes)
            quit()
p.run(commandLineParams())
stdout.write(p.help)
quit(1)
