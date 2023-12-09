.PHONY: clean all desktop posix mac macintel macarm linux linux32 linux64 arm arm32 arm64 windows win32 win64 local install install-only run docker help


# needs to be defined before include
default:help

include config.mk

DEST:=~/Works/System/bin/arch

ifeq ($(shell which nim 2>/dev/null),)
LOCALNIM=~/.nimble/bin/nim
else
LOCALNIM=$(shell which nim)
endif

ifeq ($(OPTIMIZE),)
OPTIMIZE=size
endif

GENERICOPTS=-d:VERSION=$(VERSION) $(NIMOPTS) --opt:$(OPTIMIZE)

ifeq ($(DEBUG),true)
BASENIMOPTS=$(GENERICOPTS)
else
ifeq ($(DEBUG),full)
BASENIMOPTS=$(GENERICOPTS) -d:debug --debuginfo --linedir:on -d:nimDebugDlOpen
else
ifeq ($(DEBUG),unsafe)
BASENIMOPTS=$(GENERICOPTS) -d:release -d:strip -d:danger
else
BASENIMOPTS=$(GENERICOPTS) -d:release -d:strip
endif
endif
endif

ifeq ($(EXECNAME),)
EXECNAME:=$(NAME)
endif

ifeq ($(VERSION),)
VERSION:=0.1
endif

ifeq ($(COMPILER),)
COMPILER:=c
endif

ifeq ($(WINAPP),)
WINAPP:=console
endif

ifeq ($(ALLTARGETS),)
ALLTARGETS:=desktop arm linux32
endif

ifneq ($(NIMBLE),)
NIMBLE:=nimble refresh ; nimble -y install $(NIMBLE);
DOCKERNAME:=teras/nimcross:${NAME}
DOCKERNAME32:=teras/nimcross32:${NAME}
DOCKERNAMEMAC:=teras/nimcrossmac:${NAME}
else
DOCKERNAME:=teras/nimcross
DOCKERNAME32:=teras/nimcross32
DOCKERNAMEMAC:=teras/nimcrossmac
endif

ifneq ($(NIMVER),)
NIMVER:=choosenim $(NIMVER);
endif

DOCOMPRESS:=$(shell echo $(COMPRESS) | tr A-Z a-z | cut -c1-1)

TYPEARG:=$(shell echo $(TYPE) | tr A-Z a-z | cut -c1-1)
ifeq ($(TYPEARG),l)
TARGETEXT=dll
else
TARGETEXT=exe
endif

BUILDDEP:=$(wildcard *.nim *.c *.m Makefile config.mk)

initlocal:
	${NIMVER} ${NIMBLE}

local:target/${EXECNAME}	## Create a binary based on locally installed nim compilers

all:$(ALLTARGETS)	## Target all platforms. The actual platforms are stored in configuration variable $ALLTARGETS

desktop:mac linux windows	## Create only desktop platforms. These are macOS, Linux and Windows

posix:mac linux arm 	## Create only POSIX-compatible platforms. These are macOS, Linux and Linux on ARM

arm:arm32 arm64 	## Create only ARM-related targets. These are Linux ARM 32 and Linux ARM 64

arm64:target/${EXECNAME}.aarch64.linux	## Create only Linux ARM 32 target

arm32:target/${EXECNAME}.arm.linux	## Create only Linux ARM 64 target

mac:target/${EXECNAME}.mac		## Create only macOS targets. These are fat macOS ARM 64 and Intel 64

macintel:target/${EXECNAME}.macintel	## Create only macOS Intel 64 target

macarm:target/${EXECNAME}.macarm	## Create only macOS ARM 64 target

linux:linux64	## Create only Linux Intel target. Currently only 64 bit is produced

linux64:target/${EXECNAME}.linux	## Create only Linux Intel (64) target

linux32:target/${EXECNAME}.linux32	## Create only Linux Intel (32) target

windows:win32 win64	 ## Create Windows target, both 32 and 64 bit

win32:target/${EXECNAME}.32.${TARGETEXT}	 ## Create Windows 32 bit target

win64:target/${EXECNAME}.64.${TARGETEXT}	 ## Create Windows 32 bit target

js:target/${EXECNAME}.js  ## Create JavaScript target

clean:	## Clean up project files
	rm -rf target docker.tmp podman.tmp nimcache ${CLEAN}

help:	## Show this message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

helpconfig:	## Show config.mk options
	@echo 'Required:'
	@echo '    NAME        The application name'
	@echo 'Recommended:'
	@echo '    VERSION     The application version'
	@echo 'Optional:'
	@echo '    ALLTARGETS  The actual targets that will be built when the "all" target is selected, defaults to [desktop, arm]'
	@echo '    COMPILER    The nim compiler to use, "c" by default'
	@echo '    COMPRESS    If the final application should be compressed by upx or not, boolean value, false by default'
	@echo '    DEBUG       Use debug build, have release build by default. Valid values: [release, debug, full, unsafe]'
	@echo '    EXECNAME    The executable name, $$NAME by default'
	@echo '    NIMBLE      A list of extra nimble packed needed. If required, then podman/docker target should be called in advance'
	@echo '    NIMOPTS     Extra nim compiler options'
	@echo '    RUNARGS     The run arguments when "run" make target is used'
	@echo '    TYPE        The type of the application, defaults to dynamically linked file. Valid values: [dynamic, static, library]'
	@echo '    WINAPP      Type of windows application, valid values [gui,console], "console" by default'

podman:	 ## If required, create specific podman containers to aid compiling this project
	@if [ "${NIMBLE}" != "" ] ; then \
		rm -rf podman.tmp && \
		mkdir podman.tmp && \
		echo >podman.tmp/Dockerfile "FROM teras/nimcross" && \
		echo >>podman.tmp/Dockerfile "RUN ${NIMBLE}" && \
		cd podman.tmp ; podman build -t ${DOCKERNAME} --no-cache . && cd .. &&\
		rm -rf podman.tmp ; \
        mkdir podman.tmp && \
        echo >podman.tmp/Dockerfile "FROM teras/nimcross32" && \
        echo >>podman.tmp/Dockerfile "RUN ${NIMBLE}" && \
        cd podman.tmp ; podman build -t ${DOCKERNAME32} --no-cache . && cd .. &&\
        rm -rf podman.tmp ; \
        mkdir podman.tmp && \
        echo >podman.tmp/Dockerfile "FROM teras/nimcrossmac" && \
        echo >>podman.tmp/Dockerfile "RUN ${NIMBLE}" && \
        cd podman.tmp ; podman build -t ${DOCKERNAMEMAC} --no-cache . && cd ..&&\
        rm -rf podman.tmp ; \
	fi

docker:	 ## If required, create specific docker containers to aid compiling this project
	@if [ "${NIMBLE}" != "" ] ; then \
		rm -rf docker.tmp && \
		mkdir docker.tmp && \
		echo >docker.tmp/Dockerfile "FROM teras/nimcross" && \
		echo >>docker.tmp/Dockerfile "RUN ${NIMBLE}" && \
		cd docker.tmp ; docker build -t ${DOCKERNAME} --no-cache . && cd .. &&\
		rm -rf docker.tmp ; \
        mkdir docker.tmp && \
        echo >docker.tmp/Dockerfile "FROM teras/nimcross32" && \
        echo >>docker.tmp/Dockerfile "RUN ${NIMBLE}" && \
        cd docker.tmp ; docker build -t ${DOCKERNAME32} --no-cache . && cd .. &&\
        rm -rf docker.tmp ; \
        mkdir docker.tmp && \
        echo >docker.tmp/Dockerfile "FROM teras/nimcrossmac" && \
        echo >>docker.tmp/Dockerfile "RUN ${NIMBLE}" && \
        cd docker.tmp ; docker build -t ${DOCKERNAMEMAC} --no-cache . && cd ..&&\
        rm -rf docker.tmp ; \
	fi

target/${EXECNAME}.macintel:${BUILDDEP}
	mkdir -p target
	@echo "** WARNING ** static binaries & libraries not supported  for macOS platform"
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAMEMAC} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${MACNIMOPTS} --os:macosx --cpu:amd64 --passC:'-mmacosx-version-min=10.7 -gfull' --passL:'-mmacosx-version-min=10.7 -dead_strip' ${NAME} && x86_64-apple-darwin22.2-strip ${NAME}"
	mv ${NAME} target/${EXECNAME}.macintel
	# if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${EXECNAME}.macintel ; fi # UPX is broken under macOS right now

target/${EXECNAME}.macarm:${BUILDDEP}
	mkdir -p target
	@echo "** WARNING ** static binaries & libraries not supported  for macOS platform"
	# Stripping is also broken
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAMEMAC} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${MACNIMOPTS} --os:macosx --cpu:arm64 --passC:'-mmacosx-version-min=10.7 -gfull' --passL:'-mmacosx-version-min=10.7 -dead_strip' ${NAME}"
	mv ${NAME} target/${EXECNAME}.macarm
	# if [ "$(DOCOMPRESS)" = "t" ] ; then podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAMEMAC} /usr/local/bin/upx --best ${EXECNAME} ; fi

target/${EXECNAME}.mac:target/${EXECNAME}.macintel target/${EXECNAME}.macarm
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAMEMAC} bash -c "lipo -create target/${NAME}.macarm target/${NAME}.macintel -output target/${NAME}.mac "

target/${EXECNAME}:${BUILDDEP}
	mkdir -p target
	$(if $(findstring l,$(TYPEARG)), $(eval TYPEPARAM=--noMain:on --app:lib))
	$(if $(findstring s,$(TYPEARG)), $(eval TYPEPARAM=--gcc.exe:$(CPREF)gcc --gcc.linkerexe:$(CPREF)gcc --passL:-static))
	${NIMVER} ${LOCALNIM} ${COMPILER} ${BASENIMOPTS} ${EXTRA} ${TYPEPARAM} -d:lto --outdir:./target ${NAME}

target/${EXECNAME}.linux:${BUILDDEP}
	mkdir -p target
	$(eval CPREF:=/cross/x86_64-linux-musl-cross/bin/x86_64-linux-musl-)
	$(eval EXTRA:=$(LINUXNIMOPTS) -d:lto)
	$(if $(findstring l,$(TYPEARG)), $(eval OUT=lib$(NAME).linux.so), $(eval OUT=$(NAME).linux))
	$(if $(findstring l,$(TYPEARG)), $(eval TYPEPARAM=--noMain:on --app:lib))
	$(if $(findstring s,$(TYPEARG)), $(eval TYPEPARAM=--gcc.exe:$(CPREF)gcc --gcc.linkerexe:$(CPREF)gcc --passL:-static))
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${EXTRA} ${TYPEPARAM} -o:./target/${OUT} ${NAME}"
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best ./target/${OUT} ; fi

target/${EXECNAME}.linux32:${BUILDDEP}
	mkdir -p target
	$(eval CPREF:=/cross/i686-linux-musl-cross/bin/i686-linux-musl-)
	$(eval EXTRA:=$(LINUXNIMOPTS) -d:lto --cpu:i386 --passC:-m32 --passL:-m32 --gcc.exe:$(CPREF)gcc --gcc.linkerexe:$(CPREF)gcc)
	$(if $(findstring l,$(TYPEARG)), $(eval OUT=lib$(NAME).32.linux), $(eval OUT=$(NAME).32.linux))
	$(if $(findstring l,$(TYPEARG)), $(eval TYPEPARAM=--noMain:on --app:lib))
	$(if $(findstring s,$(TYPEARG)), $(eval TYPEPARAM=--passL:-static))
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME32} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${EXTRA} ${TYPEPARAM} -o:./target/${OUT} ${NAME}"
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${OUT} ; fi

target/${EXECNAME}.arm.linux:${BUILDDEP}
	mkdir -p target
	$(eval CPREF:=/cross/armel-linux-musleabihf-cross/bin/armel-linux-musleabihf-)
	$(eval EXTRA:=$(PINIMOPTS) -d:lto --cpu:arm --os:linux)
	$(if $(findstring l,$(TYPEARG)), $(eval OUT=lib$(NAME).arm.linux.so), $(eval OUT=$(NAME).arm.linux))
	$(if $(findstring l,$(TYPEARG)), $(eval TYPEPARAM=--noMain:on --app:lib))
	$(if $(findstring s,$(TYPEARG)), $(eval TYPEPARAM=--gcc.exe:$(CPREF)gcc --gcc.linkerexe:$(CPREF)gcc --passL:-static))
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${EXTRA} ${TYPEPARAM} -o:./target/${OUT} ${NAME}"
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${OUT} ; fi

target/${EXECNAME}.aarch64.linux:${BUILDDEP}
	mkdir -p target
	$(eval CPREF:=/cross/aarch64-linux-musl-cross/bin/aarch64-linux-musl-)
	$(eval EXTRA:=$(PINIMOPTS) -d:lto --cpu:arm64 --os:linux)
	$(if $(findstring l,$(TYPEARG)), $(eval OUT=lib$(NAME).aarch64.linux.so), $(eval OUT=$(NAME).aarch64.linux))
	$(if $(findstring l,$(TYPEARG)), $(eval TYPEPARAM=--noMain:on --app:lib))
	$(if $(findstring s,$(TYPEARG)), $(eval TYPEPARAM=--gcc.exe:$(CPREF)gcc --gcc.linkerexe:$(CPREF)gcc --passL:-static))
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${EXTRA} ${TYPEPARAM} -o:./target/${OUT} ${NAME}"
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${OUT} ; fi

target/${EXECNAME}.32.${TARGETEXT}:${BUILDDEP}
	mkdir -p target
	$(eval CPREF:=/cross/i686-w64-mingw32-cross/bin/i686-w64-mingw32-)
	$(eval EXTRA:=$(WINDOWSNIMOPTS) -d:lto -d:mingw --cpu:i386 --app:$(WINAPP))
	$(if $(findstring l,$(TYPEARG)), $(eval OUT=$(NAME).32.dll), $(eval OUT=$(NAME).32.exe))
	$(if $(findstring l,$(TYPEARG)), $(eval TYPEPARAM=--noMain:on --app:lib))
	$(if $(findstring s,$(TYPEARG)), $(eval TYPEPARAM=--gcc.exe:$(CPREF)gcc --gcc.linkerexe:$(CPREF)gcc --passL:-static))
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${EXTRA} ${TYPEPARAM} -o:./target/${OUT} ${NAME}"
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${OUT} ; fi

target/${EXECNAME}.64.${TARGETEXT}:${BUILDDEP}
	mkdir -p target
	$(eval CPREF:=/cross/x86_64-w64-mingw32-cross/bin/x86_64-w64-mingw32-)
	$(eval EXTRA:=$(WINDOWSNIMOPTS) -d:lto -d:mingw --cpu:amd64 --app:$(WINAPP))
	$(if $(findstring l,$(TYPEARG)), $(eval OUT=$(NAME).64.dll), $(eval OUT=$(NAME).64.exe))
	$(if $(findstring l,$(TYPEARG)), $(eval TYPEPARAM=--noMain:on --app:lib))
	$(if $(findstring s,$(TYPEARG)), $(eval TYPEPARAM=--gcc.exe:$(CPREF)gcc --gcc.linkerexe:$(CPREF)gcc --passL:-static))
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${EXTRA} ${TYPEPARAM} -o:./target/${OUT} ${NAME}"
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${OUT} ; fi

target/${EXECNAME}.js:${BUILDDEP}
	mkdir -p target
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim js ${BASENIMOPTS} ${NAME}"
	mv ${NAME}.js target/${EXECNAME}.js
	if [ "$(DOCOMPRESS)" = "t" ] ; then uglifyjs target/${EXECNAME}.js >target/${EXECNAME}.min.js ; mv target/${EXECNAME}.min.js target/${EXECNAME}.js ; fi
	echo > target/index.html "<!DOCTYPE html>"
	echo >>target/index.html '<html><head><meta charset="UTF-8"/><link href="styles.css" rel="stylesheet" type="text/css"></head><body id="body" class="site"><div id="ROOT"></div><script type="text/javascript" src="/'${EXECNAME}'.js"></script></body></html>'

install: | all install-only		## Create and install binaries to default location

install-only:	## Only install binaries, without rebuilding them
	set -e ; mkdir -p ${DEST}/all
	set -e ; rm -rf ${DEST}/all/${EXECNAME}.* ; rm -f ${DEST}/darwin-arm64/${EXECNAME} ${DEST}/darwin-x86_64/${EXECNAME} ${DEST}/darwin/${EXECNAME} ${DEST}/linux-x86_64/${EXECNAME} ${DEST}/linux-i386/${EXECNAME} ${DEST}/linux-arm/${EXECNAME} ${DEST}/linux-aarch64/${EXECNAME} ${DEST}/windows-x86_64/${EXECNAME}.exe ${DEST}/windows-i686/${EXECNAME}.exe ${DEST}/windows-x86_64/${EXECNAME}.dll ${DEST}/windows-i686/${EXECNAME}.dll
	set -e ; if [ -f target/${EXECNAME}.linux         ] ; then mkdir -p ${DEST}/linux-x86_64   && cp target/${EXECNAME}.linux         ${DEST}/all/ && ln -s ../all/${EXECNAME}.linux         ${DEST}/linux-x86_64/${EXECNAME}       ; fi
	set -e ; if [ -f target/${EXECNAME}.linux32       ] ; then mkdir -p ${DEST}/linux-i386     && cp target/${EXECNAME}.linux32       ${DEST}/all/ && ln -s ../all/${EXECNAME}.linux32       ${DEST}/linux-i386/${EXECNAME}         ; fi
	set -e ; if [ -f target/${EXECNAME}.arm.linux     ] ; then mkdir -p ${DEST}/linux-arm      && cp target/${EXECNAME}.arm.linux     ${DEST}/all/ && ln -s ../all/${EXECNAME}.arm.linux     ${DEST}/linux-arm/${EXECNAME}          ; fi
	set -e ; if [ -f target/${EXECNAME}.aarch64.linux ] ; then mkdir -p ${DEST}/linux-aarch64  && cp target/${EXECNAME}.aarch64.linux ${DEST}/all/ && ln -s ../all/${EXECNAME}.aarch64.linux ${DEST}/linux-aarch64/${EXECNAME}      ; fi
	set -e ; if [ -f target/${EXECNAME}.64.exe        ] ; then mkdir -p ${DEST}/windows-x86_64 && cp target/${EXECNAME}.64.exe        ${DEST}/all/ && ln -s ../all/${EXECNAME}.64.exe        ${DEST}/windows-x86_64/${EXECNAME}.exe ; fi
	set -e ; if [ -f target/${EXECNAME}.32.exe        ] ; then mkdir -p ${DEST}/windows-i686   && cp target/${EXECNAME}.32.exe        ${DEST}/all/ && ln -s ../all/${EXECNAME}.32.exe        ${DEST}/windows-i686/${EXECNAME}.exe   ; fi
	set -e ; if [ -f target/${EXECNAME}.64.dll        ] ; then mkdir -p ${DEST}/windows-x86_64 && cp target/${EXECNAME}.64.dll        ${DEST}/all/ && ln -s ../all/${EXECNAME}.64.exe        ${DEST}/windows-x86_64/${EXECNAME}.exe ; fi
	set -e ; if [ -f target/${EXECNAME}.32.dll        ] ; then mkdir -p ${DEST}/windows-i686   && cp target/${EXECNAME}.32.dll        ${DEST}/all/ && ln -s ../all/${EXECNAME}.32.exe        ${DEST}/windows-i686/${EXECNAME}.exe   ; fi
	set -e ; if [ -f target/${EXECNAME}.macarm        ] ; then mkdir -p ${DEST}/darwin-arm64   && cp target/${EXECNAME}.macarm        ${DEST}/all/ && ln -s ../all/${EXECNAME}.macarm        ${DEST}/darwin-arm64/${EXECNAME}       ; fi
	set -e ; if [ -f target/${EXECNAME}.macintel      ] ; then mkdir -p ${DEST}/darwin-x86_64  && cp target/${EXECNAME}.macintel      ${DEST}/all/ && ln -s ../all/${EXECNAME}.macintel      ${DEST}/darwin-x86_64/${EXECNAME}      ; fi
	set -e ; if [ -f target/${EXECNAME}.mac           ] ; then mkdir -p ${DEST}/darwin         && cp target/${EXECNAME}.mac           ${DEST}/all/ && ln -s ../all/${EXECNAME}.mac           ${DEST}/darwin/${EXECNAME}             ; fi

run:local	## Run the executable based on the config property $RUNARGS
	./target/${EXECNAME} ${RUNARGS}
