import strutils, sequtils

type OSType* = enum
  pMacos, pLinux64, pLinuxArm32, pLinuxArm64, pWin32, pWin64, pGeneric

type Assoc* = object
  extension*: string
  description*: string
  mime*: string

proc `$`*(ostype:OSType):string = system.`$`(ostype).substr(1).toLowerAscii

proc typesList*():string = OSType.mapIt($it).join(", ")

proc icon*(ostype:OSType, filename:string):string = return case ostype:
  of pMacos: filename & ".icns"
  of pWin32, pWin64: filename & ".ico"
  of pLinux64, pLinuxArm32, pLinuxArm64, pGeneric: filename & ".png"

proc appx*(ostype:OSType):string = return case ostype:
  of pMacos: "app"
  of pWin32: "w32"
  of pWin64: "w64"
  of pLinux64: "x86_64.appdir"
  of pLinuxArm32: "arm.appdir"
  of pLinuxArm64: "aarch64.appdir"
  of pGeneric: "generic"

proc packx*(ostype:OSType):string = return case ostype:
  of pMacos: "dmg"
  of pWin64: "x64.exe"
  of pWin32: "x32.exe"
  of pLinux64: "x86_64.appimage"
  of pLinuxArm32: "arm.appimage"
  of pLinuxArm64: "aarch64.appimage"
  of pGeneric: "tar.bz2"

proc bits*(ostype:OSType):int = return if ($ostype).contains("32"): 32 else: 64

const linuxTargets* = @[pLinux64, pLinuxArm32, pLinuxArm64]
const windowsTargets* = @[pWin32, pWin64]