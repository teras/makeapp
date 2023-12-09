import strutils, sequtils, autos, os

type OSType* = enum
  pMacos, pLinux64, pLinuxArm32, pLinuxArm64, pWin32, pWin64, pGeneric

type Assoc* = object
  extension*: string
  description*: string
  mime*: string

type Resource* = object
  base*:string
  gen*:string

proc `$`*(ostype:OSType):string = system.`$`(ostype).substr(1).toLowerAscii

proc typesList*():string = OSType.mapIt($it).join(", ")

proc jrearch*(ostype:OSType):string = return case ostype:
  of pMacos: "macin"
  of pWin32: "win32"
  of pWin64: "win64"
  of pLinux64: "lin64"
  of pLinuxArm32: "arm32"
  of pLinuxArm64: "arm64"
  of pGeneric: "none"

proc appx*(ostype:OSType):string = return case ostype:
  of pMacos: "app"
  of pWin32: "w32"
  of pWin64: "w64"
  of pLinux64: "x86_64.appdir"
  of pLinuxArm32: "arm.appdir"
  of pLinuxArm64: "aarch64.appdir"
  of pGeneric: "generic"

proc cpu*(ostype:OSType):string = return case ostype:
  of pMacos, pLinux64, pWin64: "x86_64"
  of pWin32: "i386"
  of pLinuxArm64: "aarch64"
  of pLinuxArm32: "armhf"
  of pGeneric: "any"

proc packx*(ostype:OSType):string = return case ostype:
  of pMacos: (when defined(macosx):"dmg" else:"zip")
  of pWin64: "x64.exe"
  of pWin32: "x32.exe"
  of pLinux64, pLinuxArm32, pLinuxArm64: ostype.cpu & ".appimage"
  of pGeneric: "tar.bz2"

proc bits*(ostype:OSType):int = return if ($ostype).contains("32"): 32 else: 64

const linuxTargets* = @[pLinux64, pLinuxArm32, pLinuxArm64]
const windowsTargets* = @[pWin32, pWin64]

proc newResource*(base:string):Resource =
  if base!="" and not base.dirExists: kill "Unable to locate directory " & base
  Resource(base:base.absolutePath, gen:if base=="":"" else:randomDir())

proc path*(resource:Resource, name:string):string =
  if resource.base == "": return ""
  let basepath = resource.base / name
  if basepath.fileExists: return basepath
  let genpath = resource.gen / name
  if genpath.fileExists: return genpath
  return ""

proc exists*(resource:Resource, name:string):bool = resource.path(name) != ""
