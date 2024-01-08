import strutils, osproc, autos, sequtils, posix, os

var P12FILE*:string
var P12PASS*:string
var NOTARY*:string
var WINCERT*:string
var WINID*:string
var WINPIN*:string

let UG_ID = when defined(windows): "1000:1000"
  else: $getuid() & ":" & $getgid()
let asPodman* = findExe("podman") != ""
let podmanExec* = if asPodman: "podman" else: "docker"
proc dockerChown*(file:string):string = 
  if asPodman: "" else: " && chown " & UG_ID & " \"" & file & "\""

type CallbackProc* = proc(message: string)
let killCallback: CallbackProc = proc(message: string) =
  kill message

proc convert(cmd:varargs[string]):string =
  var first = true
  for entry in cmd:
    if not first: result.add(" ")
    else: first = false
    result.add entry.quoteShell

proc toSafe*(msg:string):string = 
  if VERBOCITY>=3: msg else: msg
    .replace(P12PASS, "[P12PASS]")
    .replace(WINID, "[WINID]")
    .replace(WINPIN, "[WINPIN]")

proc myexecImpl(reason:string, onError:CallbackProc, cmd:varargs[string], quiet:bool, canfail=false):string =
  let cmd = cmd.convert
  if reason != "": info reason
  if VERBOCITY>=2: echo "▹▹ " & cmd.toSafe
  var (txt,res) = execCmdEx(cmd, options={poUsePath, poStdErrToStdOut})
  if res != 0:
    if not quiet:
      if VERBOCITY<=1: echo "▹▹ " & cmd.toSafe
      stdout.write txt.toSafe
      stdout.flushFile
      if not canfail:
        kill ": " & reason & " (" & $res & ")"
  elif VERBOCITY>=1:
    stdout.write txt.toSafe
    stdout.flushFile
  return txt

proc myexecQuiet*(reason:string, cmd:varargs[string]):string {.discardable.} = myexecImpl(reason, killCallback, cmd, true)

proc myexec*(reason:string, onError:CallbackProc, cmd:varargs[string]):string {.discardable.} = myexecImpl(reason, onError, cmd, false)
proc myexec*(reason:string, cmd:varargs[string]):string {.discardable.} = myexecImpl(reason, killCallback, cmd, false)

proc myexecprobably*(reason:string, cmd:varargs[string]):string {.discardable.} = myexecImpl(reason, killCallback, cmd, false, true)

proc podmanImpl(reason:string, cmd:varargs[string], asUser:bool = false):string {.discardable.} =
  if asPodman or not asUser:
    myexecImpl(reason, killCallback, concat(@[podmanExec, "run", "--rm"], @cmd), false)
  else:
    myexecImpl(reason, killCallback, concat(@[podmanExec, "run", "--rm", "-u" & UG_ID], @cmd), false)
proc podman*(reason:string, cmd:varargs[string]):string {.discardable.} = podmanImpl(reason, cmd, false)
proc podmanUser*(reason:string, cmd:varargs[string]):string {.discardable.} = podmanImpl(reason, cmd, true)

