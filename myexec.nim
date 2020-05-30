import strutils, osproc, os

var USER*:string
var PASSWORD*:string
var ID*:string

var VERBOCITY*: int = 0

var ENTITLEMENTS*:string = ""
var use_temp_entitlements* = false

proc terminate(message:string, error=true) =
    if not error and use_temp_entitlements: ENTITLEMENTS.removeFile
    echo (if error:"** Error" else:"Success") & (if message!="": " " & message else:"")
    quit(if error:1 else:0)

proc exit*() = terminate("", error=false)

proc kill*(message:string) = terminate(message)

proc myexec*(reason:string, cmd:string):string {.discardable.} =
    proc printCmd() = echo "▹▹ " & (if VERBOCITY>=3: cmd else: cmd.replace(ID, "[ID]")).replace(USER, "[USER]").replace(PASSWORD, "[PASSWORD]")
    if reason != "": echo reason
    if VERBOCITY>=2: printCmd()
    var (txt,res) = execCmdEx(cmd, options={poUsePath, poStdErrToStdOut})
    if res != 0:
        if VERBOCITY<=1: printCmd()
        stdout.write txt
        stdout.flushFile
        kill ": " & reason & " (" & $res & ")"
    elif VERBOCITY>=1:
        stdout.write txt
        stdout.flushFile
    return txt

