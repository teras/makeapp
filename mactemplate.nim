

proc getCfg(name,version,id,mainjar,cp,mainclass:string):string = 
  return """
[Application]
app.name=""" & name & """

app.version=""" & version & """

app.runtime=$ROOTDIR/runtime
app.identifier=""" & id & """

app.classpath=""" & cp & """

app.mainjar=""" & mainjar & """

app.mainclass=""" & mainclass & """


[JavaOptions]

[ArgOptions]
"""

proc demo() =
  discard getCfg("name", "version", "some.id", "$ROOTDIR/app/ajar.jar", "$ROOTDIR/app/ajar.jar", "cls.Main")