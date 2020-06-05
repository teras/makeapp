import os, osproc, strutils, argparse, myexec, autos

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

proc sendToApple*(bundleId:string, fileToSend:string, asc_provider:string) =
  info "Bundle ID: " & bundleId
  info "File: " & fileToSend
  if not fileToSend.endsWith(".dmg") and not fileToSend.endsWith(".zip"): kill "Only .dmg and .zip files supported for notarizing, given " & fileToSend

  var args = @["xcrun", "altool", "-t", "osx", "-f", fileToSend, "--primary-bundle-id", bundleId, "--notarize-app", "--username", USER, "--password", PASSWORD]
  if asc_provider != "":
    args.add("--asc-provider")
    args.add(asc_provider)
  let send = myexec("Send to Apple", args)
  var uuid = findUUID(send)
  info "UUID: " & uuid

  var checkcmd = @["xcrun", "altool", "--notarization-info", uuid, "-u", USER, "-p", PASSWORD]
  if asc_provider != "":
    checkcmd.add("--asc-provider")
    checkcmd.add(asc_provider)
  while true:
    sleep SLEEP * 1000
    let check = myexec("Check status after sleeping for " & $SLEEP & "\"", checkcmd)
    if check.contains("Package Approved"):
      if fileToSend.endsWith(".dmg"):
        myexec "Stapling DMG", "xcrun", "stapler", "staple", "-v", fileToSend
      exit()
    elif not check.contains("in progress"):
      if VERBOCITY < 1:
        stdout.write check
        stdout.flushFile
      kill("")


