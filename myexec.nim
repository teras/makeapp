import strutils, osproc, autos

var USER*:string
var PASSWORD*:string
var ID*:string
var VERBOCITY*: int = 0

proc myexecImpl(reason:string, cmd:string, quiet:bool):string =
  proc printCmd() = echo "▹▹ " & (if VERBOCITY>=3: cmd else: cmd.replace(ID, "[ID]")).replace(USER, "[USER]").replace(PASSWORD, "[PASSWORD]")
  if reason != "": echo reason
  if VERBOCITY>=2: printCmd()
  var (txt,res) = execCmdEx(cmd, options={poUsePath, poStdErrToStdOut})
  if res != 0:
    if not quiet:
      if VERBOCITY<=1: printCmd()
      stdout.write txt
      stdout.flushFile
      kill ": " & reason & " (" & $res & ")"
  elif VERBOCITY>=1:
    stdout.write txt
    stdout.flushFile
  return txt

proc myexecQuiet*(reason:string, cmd:string):string {.discardable.} = myexecImpl(reason, cmd, true)

proc myexec*(reason:string, cmd:string):string {.discardable.} = myexecImpl(reason, cmd, false)
