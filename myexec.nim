import strutils, osproc, autos

var USER*:string
var PASSWORD*:string
var ID*:string

proc convert(cmd:varargs[string]):string =
  var first = true
  for entry in cmd:
    if not first: result.add(" ")
    else: first = false
    result.add entry.quoteShell

proc myexecImpl(reason:string, cmd:varargs[string], quiet:bool):string =
  let cmd = cmd.convert
  proc printCmd() = echo "▹▹ " & (if VERBOCITY>=3: cmd else: cmd.replace(ID, "[ID]")).replace(USER, "[USER]").replace(PASSWORD, "[PASSWORD]") # no call to 'info', so that command will be displayed even on error
  if reason != "": info reason
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

proc myexecQuiet*(reason:string, cmd:varargs[string]):string {.discardable.} = myexecImpl(reason, cmd, true)

proc myexec*(reason:string, cmd:varargs[string]):string {.discardable.} = myexecImpl(reason, cmd, false)
