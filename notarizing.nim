import parsecfg, plists, argparse, sets
import sendtoapple, sign, helper

const PASS_CORE_LOC = ".ssh/notarizing"

let config = loadConfig(getHomeDir() & PASS_CORE_LOC)
const p = newParser("notarizing"):
    help("Notarize and sign DMG files for the Apple store, to make later versions of macOS happy. For more info check https://github.com/teras/notarizing")
    command("sign"):
        option("-t", "--target", help="The location of the target file (DMG or Application.app). When missing the system will scan the directory tree below this point")
        option("-i", "--signid", help="The sign id, as given by `security find-identity -v -p codesigning`")
        option("-x", "--allowedext", multiple=true, help="Allow this file extension as an executable, along the default ones. Could be used more than once")
        option("-e", "--entitlements", help="Use the provided file as entitlements")
        run:
            let signid = if opts.signid != "" : opts.signid else: config.getSectionValue("", "SIGN_ID")
            if signid == "": quit("No sign id provided")
            var target = findApp(if opts.target != "": opts.target else: getCurrentDir())
            if target == "": target = findDmg(if opts.target != "": opts.target else: getCurrentDir())
            if target == "": quit("No target file provided")
            if opts.entitlements != "" and not opts.entitlements.fileExists: quit("Required entitlemens file " & opts.entitlements & " does not exist")
            sign(target, signid, opts.entitlements, opts.allowedext.toHashSet)
            quit()
    command("send"):
        option("-t", "--target", help="The location of the DMG file. When missing the system will scan the directory tree below this point")
        option("-b", "--bundleid", help="The required BundleID. When missing, the system guess from existing PList files inside an .app folder")
        option("-p", "--password", help="The location of the password file. Defaults to ~/" & PASS_CORE_LOC)
        option("-u", "--user", help="The Apple username")
        option("-a", "--ascprovider", help="The specific associated provider for the current Apple developer account")
        run:
            let password = if opts.password != "": opts.password else: config.getSectionValue("","APPLE_APP_PASSWORD")
            if password == "": quit("No password provided")
            let user = if opts.user != "": opts.user else: config.getSectionValue("", "USER")
            if user == "": quit("No user provided")
            let plist = findPlist(if opts.target != "": opts.target else: getCurrentDir())
            let bundleId = if opts.bundleid != "": opts.bundleid else: loadPlist(plist).getOrDefault("CFBundleIdentifier").getStr("")
            if bundleId == "": quit("No Bundle ID provided")
            let dmg = findDmg(if opts.target != "": opts.target else: getCurrentDir())
            if dmg == "": quit("No target file provided")
            let asc_provider = if opts.ascprovider != "": opts.ascprovider else: config.getSectionValue("", "ASC_PROVIDER")
            sendToApple(bundleId, dmg, user, password, asc_provider)
            quit()
p.run(commandLineParams())
quit("Please select a valid command, use the --help argument to see a list of commands")