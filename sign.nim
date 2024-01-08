import os, strutils, myexec, types, autos

#{.compile: "fileloader.c".}
#proc needsSigning(path:cstring):bool {.importc, used.}
#parameter is file.full.cstring.needsSigning

let expect = """#!/usr/bin/expect -f
set pin [lindex $argv 0]
set timeout 30
spawn osslsigncode sign -pkcs11module /usr/lib/libeToken.so -certs /home/vagrant/cert.pem -key 0:@ID@ -ts http://ts.harica.gr -in "/data/@IN@" -out "/data/@OUT@"
expect "Enter PKCS#11 token PIN for Panagiotis Katsaloulis:"
send -- "$pin\r"
expect eof
"""

let vagrant = """# -*- mode: ruby -*-

Vagrant.configure("2") do |config|
  config.vm.box = "generic/ubuntu2204"

  config.vm.provider :libvirt do |libvirt|
    libvirt.memory = 8192
    libvirt.memorybacking :access, :mode => "shared"
    libvirt.usb :vendor => "0x08e6", :product => "0x3438", :startupPolicy => "mandatory"
    libvirt.default_prefix = "@APP@_"
  end

  config.vm.provision "file", source: "@CERT@", destination: "/home/vagrant/cert.pem"
  config.vm.provision "file", source: "@EXPECT@", destination: "/home/vagrant/expect.exp"

  config.vm.provision "shell", inline: <<-SHELL
     apt-get update
     apt-get install -y libengine-pkcs11-openssl opensc osslsigncode opensc-pkcs11 expect
     
     wget -O /usr/bin/sign.exp https://github.com/teras/makeapp/raw/master/resources/sign.exp
     chmod a+x /usr/bin/sign.exp

     wget https://github.com/teras/makeapp/raw/master/resources/safenetauthenticationclient-core_10.8.1050_amd64.deb
     dpkg -i /home/vagrant/safenetauthenticationclient-core_10.8.1050_amd64.deb 
     rm safenetauthenticationclient-core_10.8.1050_amd64.deb

     chmod a+x /home/vagrant/expect.exp
  SHELL

  config.vm.synced_folder ".", "/data", type: "virtiofs"

end
"""

let clenupVagrant: CallbackProc = proc(message: string) =
  if not KEEPONERROR:
    myexec "Cleanup vagrant", "vagrant", "destroy", "--force"
  if message.len != 0:
    kill message

proc signWindows(target,name:string) =
  let currentDirectory = getCurrentDir()
  let parentDir = target.parentDir
  let signed = target.extractFilename
  let unsigned = signed & ".unsigned"
  target.moveFile(parentDir / unsigned)
  let vagrantFile = parentDir / "Vagrantfile"
  let expectFile = parentDir / "expect.exp"
  parentDir.setCurrentDir
  vagrantFile.writeFile(vagrant.replace("@APP@", name).replace("@CERT@", WINCERT).replace("@EXPECT@", expectFile))
  expectFile.writeFile(expect.replace("@ID@", WINID).replace("@IN@", unsigned).replace("@OUT@", signed))
  myexec "Launching Vagrant.", clenupVagrant,
    "vagrant", "up", "--provision"
  let signTxt = myexec("Signing executable", clenupVagrant, 
    "vagrant", "ssh", "-c", "~/expect.exp " & WINPIN)
  clenupVagrant("")
  if not (parentDir / signed).fileExists: 
    stdout.write signTxt.toSafe
    stdout.flushFile
    kill "Unable to create signed file " & signed
  (parentDir/unsigned).removeFile
  currentDirectory.setCurrentDir

proc notarizeMacOS*(path:string) =
  myexec "Notarize file " & path.extractFilename, "rcodesign", "notary-submit", "--api-key-file", NOTARY, "--staple", path

proc signMacOS*(path:string) =
  let ftype = if path.dirExists: "directory" elif path.endsWith(".dmg"): "DMG file" else: "file"
  myexec "Sign " & ftype & " " & path.extractFilename & " ", "rcodesign", "sign", "--p12-file", P12FILE, "--p12-password-file", P12PASS, "--code-signature-flags", "runtime", path

proc signApp*(os:seq[OSType], target, name:string) =
  for cos in os:
    case cos:
      of pMacos:
        signMacOS(target)
      of pWin32,pWin64:
        signWindows(target, name)
      else: discard
