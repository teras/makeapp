.PHONY: clean all desktop posix osx linux linux32 linux64 arm arm32 arm64 windows win32 win64 local install install-only run docker help


# needs to be defined before include
default:help

include config.mk

DEST:=~/Works/System/bin/arch

ifeq ($(OPTIMIZE),)
OPTIMIZE:=size
endif

ifeq ($(DEBUG),true)
BASENIMOPTS=-d:VERSION=$(VERSION) --opt:$(OPTIMIZE) $(NIMOPTS)
else
ifeq ($(DEBUG),full)
BASENIMOPTS=-d:VERSION=$(VERSION) --debuginfo --linedir:on $(NIMOPTS)
else
BASENIMOPTS=-d:release -d:VERSION=$(VERSION) --opt:$(OPTIMIZE) $(NIMOPTS)
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
ALLTARGETS:=desktop arm
endif

ifneq ($(NIMBLE),)
NIMBLE:=nimble refresh ; nimble -y install $(NIMBLE);
DOCKERNAME:=teras/nimcross:${NAME}
DOCKERNAME32:=teras/nimcross32:${NAME}
DOCKERNAMEOSX:=teras/nimcrossosx:${NAME}
else
DOCKERNAME:=teras/nimcross
DOCKERNAME32:=teras/nimcross32
DOCKERNAMEOSX:=teras/nimcrossosx
endif

ifneq ($(NIMVER),)
NIMVER:=choosenim $(NIMVER);
endif

DOCOMPRESS:=$(shell echo $(COMPRESS) | tr A-Z a-z | cut -c1-1)

BUILDDEP:=$(wildcard *.nim *.c *.m Makefile config.mk)

initlocal:
	${NIMVER} ${NIMBLE}

local:target/${EXECNAME}	## Create a binary based on locally installed nim compilers

all:$(ALLTARGETS)	## Target all platforms. The actual platforms are stored in configuration variable $ALLTARGETS

desktop:osx linux windows	## Create only desktop platforms. These are macOS, Linux and Windows

posix:osx linux arm 	## Create only POSIX-compatible platforms. These are macOS, Linux and Linux on ARM

arm:arm32 arm64 	## Create only ARM-related targets. These are Linux ARM 32 and Linux ARM 64

arm64:target/${EXECNAME}.aarch64.linux	## Create only Linux ARM 32 target

arm32:target/${EXECNAME}.arm.linux	## Create only Linux ARM 64 target

osx:target/${EXECNAME}.osx	## Create only macOS target

linux:linux64	## Create only Linux Intel target. Currently only 64 bit is produced

linux64:target/${EXECNAME}.linux	## Create only Linux Intel (64) target

linux32:target/${EXECNAME}.linux32	## Create only Linux Intel (32) target

windows:win32 win64	 ## Create Windows target, both 32 and 64 bit

win32:target/${EXECNAME}.32.exe	 ## Create Windows 32 bit target

win64:target/${EXECNAME}.64.exe	 ## Create Windows 32 bit target

clean:	## Clean up project files
	rm -rf target docker.tmp podman.tmp nimcache ${NAME} ${NAME}.exe ${CLEAN}

help:	## Show this message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

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
        echo >podman.tmp/Dockerfile "FROM teras/nimcrossosx" && \
        echo >>podman.tmp/Dockerfile "RUN ${NIMBLE}" && \
        cd podman.tmp ; podman build -t ${DOCKERNAMEOSX} --no-cache . && cd ..&&\
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
        echo >docker.tmp/Dockerfile "FROM teras/nimcrossosx" && \
        echo >>docker.tmp/Dockerfile "RUN ${NIMBLE}" && \
        cd docker.tmp ; docker build -t ${DOCKERNAMEOSX} --no-cache . && cd ..&&\
        rm -rf docker.tmp ; \
	fi


target/${EXECNAME}:${BUILDDEP}
	nim ${COMPILER} ${BASENIMOPTS} ${OSXNIMOPTS} ${NAME}
	mkdir -p target
	mv ${NAME} target/${EXECNAME}
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx target/${EXECNAME} ; fi

target/${EXECNAME}.osx:${BUILDDEP}
	mkdir -p target
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAMEOSX} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${OSXNIMOPTS} --os:macosx --passC:'-mmacosx-version-min=10.7 -gfull' --passL:'-mmacosx-version-min=10.7 -dead_strip' ${NAME} && x86_64-apple-darwin19-strip ${NAME}"
	mv ${NAME} target/${EXECNAME}.osx
	# if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${EXECNAME}.osx ; fi # UPX is broken under OSX right now

target/${EXECNAME}.linux:${BUILDDEP}
	mkdir -p target
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${LINUXNIMOPTS} ${NAME} && strip ${NAME}"
	mv ${NAME} target/${EXECNAME}.linux
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${EXECNAME}.linux ; fi

target/${EXECNAME}.linux32:${BUILDDEP}
	mkdir -p target
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME32} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${LINUXNIMOPTS} --cpu:i386 --passC:-m32 --passL:-m32 ${NAME} && strip ${NAME} ; if [ \"$(DOCOMPRESS)\" = \"t\" ] ; then upx --best ${NAME} ; fi"
	mv ${NAME} target/${EXECNAME}.linux32
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${EXECNAME}.linux32 ; fi

target/${EXECNAME}.arm.linux:${BUILDDEP}
	mkdir -p target
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${PINIMOPTS} --cpu:arm --os:linux ${NAME} && arm-linux-gnueabi-strip ${NAME}"
	mv ${NAME} target/${EXECNAME}.arm.linux
	patchelf --set-interpreter /lib/ld-linux-armhf.so.3 target/${EXECNAME}.arm.linux
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${EXECNAME}.arm.linux ; fi

target/${EXECNAME}.aarch64.linux:${BUILDDEP}
	mkdir -p target
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${PINIMOPTS} --cpu:arm64 --os:linux ${NAME} && aarch64-linux-gnu-strip ${NAME}"
	mv ${NAME} target/${EXECNAME}.aarch64.linux
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${EXECNAME}.aarch64.linux ; fi

target/${EXECNAME}.32.exe:${BUILDDEP}
	mkdir -p target
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${WINDOWSNIMOPTS} -d:mingw --cpu:i386  --app:${WINAPP} ${NAME} && i686-w64-mingw32-strip ${NAME}.exe"
	mv ${NAME}.exe target/${EXECNAME}.32.exe
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${EXECNAME}.32.exe ; fi

target/${EXECNAME}.64.exe:${BUILDDEP}
	mkdir -p target
	podman run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${WINDOWSNIMOPTS} -d:mingw --cpu:amd64 --app:${WINAPP} ${NAME} && x86_64-w64-mingw32-strip ${NAME}.exe"
	mv ${NAME}.exe target/${EXECNAME}.64.exe
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${EXECNAME}.64.exe ; fi


install: | all install-only		## Create and install binaries to default location

install-only:	## Only install binaries, without rebuilding them
	set -e ; mkdir -p ${DEST}/all
	set -e ; rm -rf ${DEST}/all/${EXECNAME}.* ; rm -f ${DEST}/darwin-x86_64/${EXECNAME} ${DEST}/linux-x86_64/${EXECNAME} ${DEST}/linux-i386/${EXECNAME} ${DEST}/linux-arm/${EXECNAME} ${DEST}/linux-aarch64/${EXECNAME} ${DEST}/windows-x86_64/${EXECNAME}.exe ${DEST}/windows-i686/${EXECNAME}.exe
	set -e ; if [ -f target/${EXECNAME}.osx           ] ; then mkdir -p ${DEST}/darwin-x86_64  && cp target/${EXECNAME}.osx           ${DEST}/all/ && ln -s ../all/${EXECNAME}.osx           ${DEST}/darwin-x86_64/${EXECNAME}      ; fi
	set -e ; if [ -f target/${EXECNAME}.linux         ] ; then mkdir -p ${DEST}/linux-x86_64   && cp target/${EXECNAME}.linux         ${DEST}/all/ && ln -s ../all/${EXECNAME}.linux         ${DEST}/linux-x86_64/${EXECNAME}       ; fi
	set -e ; if [ -f target/${EXECNAME}.linux32       ] ; then mkdir -p ${DEST}/linux-i386     && cp target/${EXECNAME}.linux32       ${DEST}/all/ && ln -s ../all/${EXECNAME}.linux32       ${DEST}/linux-i386/${EXECNAME}         ; fi
	set -e ; if [ -f target/${EXECNAME}.arm.linux     ] ; then mkdir -p ${DEST}/linux-arm      && cp target/${EXECNAME}.arm.linux     ${DEST}/all/ && ln -s ../all/${EXECNAME}.arm.linux     ${DEST}/linux-arm/${EXECNAME}          ; fi
	set -e ; if [ -f target/${EXECNAME}.aarch64.linux ] ; then mkdir -p ${DEST}/linux-aarch64  && cp target/${EXECNAME}.aarch64.linux ${DEST}/all/ && ln -s ../all/${EXECNAME}.aarch64.linux ${DEST}/linux-aarch64/${EXECNAME}      ; fi
	set -e ; if [ -f target/${EXECNAME}.64.exe        ] ; then mkdir -p ${DEST}/windows-x86_64 && cp target/${EXECNAME}.64.exe        ${DEST}/all/ && ln -s ../all/${EXECNAME}.64.exe        ${DEST}/windows-x86_64/${EXECNAME}.exe ; fi
	set -e ; if [ -f target/${EXECNAME}.32.exe        ] ; then mkdir -p ${DEST}/windows-i686   && cp target/${EXECNAME}.32.exe        ${DEST}/all/ && ln -s ../all/${EXECNAME}.32.exe        ${DEST}/windows-i686/${EXECNAME}.exe   ; fi

run:local	## Run the executable based on the config property $RUNARGS
	./target/${EXECNAME} ${RUNARGS}
