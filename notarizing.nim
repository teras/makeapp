import parsecfg, plists, argparse
import sendtoapple, sign, helper

const PASS_CORE_LOC = ".ssh/notarizing"

const p = newParser("notarizing"):
    help("Notarize and sign DMG files for the Apple store, to make later versions of macOS happy. For more info check https://github.com/teras/notarizing")
    arg("command", help="The command type, should be either 'send' or 'sign'")
    option("-b", "--bundleid", help="The required BundleID. When missiing the system guess from existing PList files inside an .app folder")
    option("-t", "--target", help="The location of the target file (DMG when sending to Apple, DIR.app when signing). When missing the system will scan the directory tree below this point")
    option("-p", "--password", help="The location of the password file. Defaults to ~/" & PASS_CORE_LOC)
    option("-u", "--user", help="The Apple username")
    option("-a", "--ascprovider", help="The specific asc provider for the current Apple developer account")
    option("-i", "--signid", help="The sign id, as given by `security find-identity -v -p codesigning`")
let opts = p.parse(commandLineParams())
if opts.help: quit()

let config = loadConfig(getHomeDir() & PASS_CORE_LOC)

if opts.command == "sign":
    let signid = if opts.signid != "" : opts.signid else: config.getSectionValue("", "SIGN_ID")
    if signid == "": quit("No sign id provided")
    let target = if opts.target != "": opts.target else: findApp()
    if target == "": quit("No target file provided")
    echo "Sign " & target
    sign(target, signid)
elif opts.command == "send":
    echo opts.password
    let password = if opts.password != "": opts.password else: config.getSectionValue("","APPLE_APP_PASSWORD")
    if password == "": quit("No password provided")
    let user = if opts.user != "": opts.user else: config.getSectionValue("", "USER")
    if user == "": quit("No user provided")
    let bundleId = if opts.bundleid != "": opts.bundleid else: loadPlist(findPlist()).getOrDefault("CFBundleIdentifier").getStr()
    if bundleId == "": quit("No Bundle ID provided")
    let target = if opts.target != "": opts.target else: findDmg()
    if target == "": quit("No target file provided")
    let asc_provider = if opts.ascprovider != "": opts.ascprovider else: config.getSectionValue("", "ASC_PROVIDER")
    echo "Send " & target
    sendToApple(bundleId, target, user, password, asc_provider)
else:
    quit("Not recognized command, use --help to get a list of possible commands")