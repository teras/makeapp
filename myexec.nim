import strutils, osproc, autos, sequtils, posix, os

var USER*:string
var PASSWORD*:string
var ID*:string
var P12PASS*:string
var GPGKEY*:string

let UG_ID = when defined(windows): "1000:1000"
  else: $getuid() & ":" & $getgid()
let asPodman* = findExe("podman") != ""
let podmanExec* = if asPodman: "podman" else: "docker"
proc dockerChown*(file:string):string = 
  if asPodman: "" else: " && chown " & UG_ID & " \"" & file & "\""


proc convert(cmd:varargs[string]):string =
  var first = true
  for entry in cmd:
    if not first: result.add(" ")
    else: first = false
    result.add entry.quoteShell

proc myexecImpl(reason:string, cmd:varargs[string], quiet:bool, canfail=false):string =
  let cmd = cmd.convert
  proc printCmd() = echo "▹▹ " & (if VERBOCITY>=3: cmd else: cmd
    .replace(ID, "[ID]")
    .replace(USER, "[USER]")
    .replace(PASSWORD, "[PASSWORD]")
    .replace(P12PASS, "[P12PASS]")
    .replace(GPGKEY, "[GPGKEY]")
    )# no call to 'info', so that command will be displayed even on error
  if reason != "": info reason
  if VERBOCITY>=2: printCmd()
  var (txt,res) = execCmdEx(cmd, options={poUsePath, poStdErrToStdOut})
  if res != 0:
    if not quiet:
      if VERBOCITY<=1: printCmd()
      stdout.write txt
      stdout.flushFile
      if not canfail:
        kill ": " & reason & " (" & $res & ")"
  elif VERBOCITY>=1:
    stdout.write txt
    stdout.flushFile
  return txt

proc myexecQuiet*(reason:string, cmd:varargs[string]):string {.discardable.} = myexecImpl(reason, cmd, true)

proc myexec*(reason:string, cmd:varargs[string]):string {.discardable.} = myexecImpl(reason, cmd, false)

proc myexecprobably*(reason:string, cmd:varargs[string]):string {.discardable.} = myexecImpl(reason, cmd, false, true)

proc podmanImpl(reason:string, cmd:varargs[string], asUser:bool = false):string {.discardable.} =
  if asPodman or not asUser:
    myexecImpl(reason, concat(@[podmanExec, "run", "--rm"], @cmd), false)
  else:
    myexecImpl(reason, concat(@[podmanExec, "run", "--rm", "-u" & UG_ID], @cmd), false)
proc podman*(reason:string, cmd:varargs[string]):string {.discardable.} = podmanImpl(reason, cmd, false)
proc podmanUser*(reason:string, cmd:varargs[string]):string {.discardable.} = podmanImpl(reason, cmd, true)

