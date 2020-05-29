import os, osproc, strutils, argparse

const UUID_HEADER="RequestUUID"
const SLEEP = 10

proc findUUID(input:string) : string =
    if not input.contains("No errors"):
        echo "**** ERROR FOUND, EXITING"
        quit(97)
    for line in splitLines(input):
        var cline = line.strip
        if cline.startsWith(UUID_HEADER):
            cline = cline.substr(UUID_HEADER.len).strip
            if cline.startsWith("="):
                return cline.substr(1).strip
    echo "Unable to locate UUID"
    quit(96)

proc sendToApple*(bundleId:string, dmg:string, user:string, password:string, asc_provider:string, shouldAsk=true) =
    echo "Bundle ID: " & bundleId
    echo "DMG: " & dmg
    echo "Username: " & user
    if asc_provider!="": echo "Associated Provider: " & asc_provider
    if shouldAsk:
        stdout.write "Press [ENTER] to continue "
        stdout.flushFile
        discard stdin.readLine

    echo "Sending DMG to Apple"
    var sendArgs = @["altool", "-t", "osx", "-f", dmg, "--primary-bundle-id", bundleId, "--notarize-app",
        "--username", user, "--password", password]
    if asc_provider != "":
        sendArgs.add("--asc-provider")
        sendArgs.add(asc_provider)
    let send = execProcess("xcrun", args=sendArgs, options={poUsePath, poStdErrToStdOut})
    echo send
    var uuid = findUUID(send)
    echo "UUID: " & uuid

    var checkArgs = @["altool", "--notarization-info", uuid, "-u", user, "-p", password]
    if asc_provider != "":
        checkArgs.add("--asc-provider")
        checkArgs.add(asc_provider)
    while true:
        echo "Sleeping for ", SLEEP, "\""
        sleep SLEEP * 1000
        echo "Check status of package"
        let check = execProcess("xcrun", args=checkArgs, options={poUsePath, poStdErrToStdOut})
        echo check

        if check.contains("Package Approved"):
            echo "Stapling DMG"
            echo execProcess("xcrun", args=["stapler", "staple", "-v", dmg], options={poUsePath, poStdErrToStdOut})
            quit(0)
        
        if not check.contains("in progress"):
            echo "**** ERROR FOUND, EXITING"
            quit(2)


