import os, osproc, strutils, argparse, myexec

const UUID_HEADER="RequestUUID"
const SLEEP = 15

proc findUUID(input:string) : string =
    if not input.contains("No errors"): kill "Error while searching for UUID"
    for line in splitLines(input):
        var cline = line.strip
        if cline.startsWith(UUID_HEADER):
            cline = cline.substr(UUID_HEADER.len).strip
            if cline.startsWith("="):
                return cline.substr(1).strip
    kill "Unable to locate UUID"

proc sendToApple*(bundleId:string, fileToSend:string, asc_provider:string, shouldAsk:bool) =
    echo "Bundle ID: " & bundleId
    echo "File: " & fileToSend
    if asc_provider!="": echo "Associated Provider: " & asc_provider
    if shouldAsk:
        stdout.write "Press [ENTER] to continue "
        stdout.flushFile
        discard stdin.readLine

    let send = myexec("Send to Apple", "xcrun altool -t osx -f " & fileToSend.quoteShell & " --primary-bundle-id " &
        bundleId.quoteShell & " --notarize-app" &
        " --username " & USER.quoteShell &  " --password " & PASSWORD.quoteShell &
        (if asc_provider != "": " --asc-provider " & asc_provider.quoteShell else:"") )
    var uuid = findUUID(send)
    echo "UUID: " & uuid

    let checkcmd = "xcrun altool --notarization-info " & uuid.quoteShell & " -u " & USER.quoteShell & " -p " & PASSWORD.quoteShell &
        (if asc_provider != "": " --asc-provider " & asc_provider.quoteShell else:"")
    while true:
        sleep SLEEP * 1000
        let check = myexec("Check status after sleeping for " & $SLEEP & "\"", checkcmd)
        if check.contains("Package Approved"):
            myexec "Stapling DMG", "xcrun stapler staple -v " & fileToSend.quoteShell
            exit()        
        elif not check.contains("in progress"):
            if VERBOCITY < 1:
                stdout.write check
                stdout.flushFile
            kill("")


