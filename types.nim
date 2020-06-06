import strutils, sequtils

type OSType* = enum
  pMacos, pLinux32, pLinux64, pWin32, pWin64

type Assoc* = object
  extension*: string
  description*: string
  mime*: string

proc `$`*(ostype:OSType):string = system.`$`(ostype).substr(1).toLowerAscii

proc typesList*():string = OSType.mapIt($it).join(", ")

proc icon*(ostype:OSType, filename:string):string = return case ostype:
  of pMacos: filename & ".icns"
  of pWin32, pWin64: filename & ".ico"
  of pLinux32, pLinux64: filename & ".png"

proc appx*(ostype:OSType):string = return case ostype:
  of pMacos: "app"
  of pWin32: "w32"
  of pWin64: "w64"
  of pLinux32: "l32"
  of pLinux64: "l64"

proc packx*(ostype:OSType):string = return case ostype:
  of pMacos: "dmg"
  of pWin64: "x64.exe"
  of pWin32: "x32.exe"
  of pLinux32: "i686.appimage"
  of pLinux64: "x86_64.appimage"

proc bits*(ostype:OSType):int = return case ostype:
  of pMacos,pWin64, pLinux64: 64
  else: 32