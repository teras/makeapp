import tables, strutils,nim_miniz, autos,os

const LAUNCHER* = ("launcher.mac").staticRead
# const APPLAUNCHERLIB* = ("libapplauncher.dylib").staticRead


proc getInfoPlist*(appname,bundleid,version,copyright:string):string =
  """
<?xml version="1.0" ?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
 <dict>
  <key>LSMinimumSystemVersion</key>
  <string>10.9</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>English</string>
  <key>CFBundleAllowMixedLocalizations</key>
  <true/>
  <key>CFBundleExecutable</key>
  <string>""" & appname & """</string>
  <key>CFBundleIconFile</key>
  <string>""" & appname & """.icns</string>
  <key>CFBundleIdentifier</key>
  <string>""" & bundleid & """</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>""" & appname & """</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>""" & version & """</string>
  <key>CFBundleSignature</key>
  <string>????</string>
  <key>LSApplicationCategoryType</key>
  <string>Unknown</string>
  <key>CFBundleVersion</key>
  <string>""" & version & """</string>
  <key>NSHumanReadableCopyright</key>
  <string>""" & copyright & """</string>
  <key>NSHighResolutionCapable</key>
  <string>true</string>
 </dict>
</plist>
"""

proc parseManifest(data:string) : TableRef[string,string] =
  proc parseManifestLine(line:string, dict:TableRef[string,string]) =
    if line.len == 0:
      return
    let colon = line.find(':')
    if colon < 1: raise newException(Exception, "Error in manifest file: no colon found")
    dict[line.substr(0, colon-1).strip.toLowerAscii] = line.substr(colon+1).strip
  result = newTable[string,string]()
  var prev = ""
  for line in data.splitLines():
    if line.len > 0:
      if line[0] == ' ':
        if prev.len == 0: raise newException(Exception, "Error in manifest file, wrong multiline argument")
        prev = prev & line.substr(1)
      else:
        if prev.len > 0: parseManifestLine(prev, result)
        prev = line
  if prev.len > 0: parseManifestLine(prev, result)

proc findMainClass(jar:string):string =
  var manifest: TableRef[string, string]
  var zip:Zip
  if not zip.open(jar): kill "Error while opening JAR file " & jar
  for i, fname in zip:
    if fname == "META-INF/MANIFEST.MF":
      manifest = parseManifest(zip.extract_file(fname, randomDir()).readFile)
  zip.close()
  return manifest["main-class"]

proc getCfg*(name,version,id,mainjar,appdir:string):string = 
  return """
[Application]
app.classpath=$APPDIR/""" & mainjar & """

app.mainclass=""" & findMainClass(appdir/mainjar) & """

app.name=""" & name & """

app.version=""" & version & """

app.identifier=""" & id & """

"""

proc getJpackageXML*(name,version:string):string =
  return """<?xml version="1.0" ?>
<jpackage-state version="15.0.1" platform="macOS">
  <app-version>""" & version & """</app-version>
  <main-launcher>""" & name & """</main-launcher></jpackage-state>"""
