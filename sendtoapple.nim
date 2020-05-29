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

proc sendToApple*(bundleId:string, fileToSend:string, user:string, password:string, asc_provider:string, shouldAsk:bool, verbose:int) =
    proc safe(input:string):string = 
        if verbose<=1:
            input.replace(user, "[USER]").replace(password, "[PASSWORD]")
        else:
            input
    echo "Bundle ID: " & bundleId
    echo "File: " & fileToSend
    echo "Username: " & user
    if asc_provider!="": echo "Associated Provider: " & asc_provider
    if shouldAsk:
        stdout.write "Press [ENTER] to continue "
        stdout.flushFile
        discard stdin.readLine

    echo "Sending DMG to Apple"
    let sendcmd = "xcrun altool -t osx -f " & fileToSend.quoteShell & " --primary-bundle-id " & bundleId.quoteShell & " --notarize-app" &
        " --username " & user.quoteShell &  " --password " & password.quoteShell & (if asc_provider != "": " --asc-provider " & asc_provider.quoteShell else:"")
    if verbose>0: echo "▹▹ " & sendcmd.safe
    let (send,_) = execCmdEx(sendcmd, options={poUsePath, poStdErrToStdOut})
    echo send
    var uuid = findUUID(send)
    echo "UUID: " & uuid

    let checkcmd = "xcrun altool --notarization-info " & uuid.quoteShell & " -u " & user.quoteShell & " -p " & password.quoteShell &
        (if asc_provider != "": " --asc-provider " & asc_provider.quoteShell else:"")
    if verbose>0: echo "▹▹ " & checkcmd.safe
    while true:
        echo "Sleeping for ", SLEEP, "\""
        sleep SLEEP * 1000
        echo "Check status of package"
        let (check,_) = execCmdEx(checkcmd, options={poUsePath, poStdErrToStdOut})
        echo check

        if check.contains("Package Approved"):
            echo "Stapling DMG"
            let staplecmd = "xcrun stapler staple -v " & fileToSend.quoteShell
            if verbose>0: echo "▹▹ " & staplecmd
            echo execCmdEx(staplecmd, options={poUsePath, poStdErrToStdOut})
            quit(0)
        
        if not check.contains("in progress"):
            echo "**** ERROR FOUND, EXITING"
            quit(2)


