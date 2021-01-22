.PHONY: clean all desktop posix osx linux linux32 linux64 arm arm32 arm64 windows win32 win64 local install install-only run docker xclean


# needs to be defined before include
default:local

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
else
DOCKERNAME:=teras/nimcross
DOCKERNAME32:=teras/nimcross32
endif

ifneq ($(NIMVER),)
NIMVER:=choosenim $(NIMVER);
endif

DOCOMPRESS:=$(shell echo $(COMPRESS) | tr A-Z a-z | cut -c1-1)

BUILDDEP:=$(wildcard *.nim *.c *.m Makefile config.mk)
UGID:=$(shell id -u):$(shell id -g)

initlocal:
	${NIMVER} ${NIMBLE}

local:target/${EXECNAME}

all:$(ALLTARGETS)

desktop:osx linux windows

posix:osx linux arm

arm:arm32 arm64

arm64:target/${EXECNAME}.aarch64.linux

arm32:target/${EXECNAME}.arm.linux

osx:target/${EXECNAME}.osx

linux:linux64

linux64:target/${EXECNAME}.linux

linux32:target/${EXECNAME}.linux32

windows:win32 win64

win32:target/${EXECNAME}.32.exe

win64:target/${EXECNAME}.64.exe

clean:xclean
	rm -rf target docker.tmp nimcache ${NAME} ${NAME}.exe


docker:
	@if [ "${NIMBLE}" != "" ] ; then \
	rm -rf docker.tmp && \
	mkdir docker.tmp && \
	echo >docker.tmp/Dockerfile "FROM teras/nimcross" && \
	echo >>docker.tmp/Dockerfile "RUN ${NIMBLE}" && \
	cd docker.tmp ; docker build -t ${DOCKERNAME} . && \
	rm -rf docker.tmp ; \
        mkdir docker.tmp && \
        echo >docker.tmp/Dockerfile "FROM teras/nimcross32" && \
        echo >>docker.tmp/Dockerfile "RUN ${NIMBLE}" && \
        cd docker.tmp ; docker build -t ${DOCKERNAME32} . && \
        rm -rf docker.tmp ; \
	fi

target/${EXECNAME}:${BUILDDEP}
	nim ${COMPILER} ${BASENIMOPTS} ${OSXNIMOPTS} ${NAME}
	mkdir -p target
	mv ${NAME} target/${EXECNAME}
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx target/${EXECNAME} ; fi
	cp target/${EXECNAME} target/${EXECNAME}.osx

target/${EXECNAME}.osx:${BUILDDEP}
	mkdir -p target
	docker run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${OSXNIMOPTS} --os:macosx --passC:'-mmacosx-version-min=10.7 -gfull' --passL:'-mmacosx-version-min=10.7 -dead_strip' ${NAME} && x86_64-apple-darwin19-strip ${NAME} && chown ${UGID} ${NAME}"
	mv ${NAME} target/${EXECNAME}.osx
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${EXECNAME}.osx ; fi

target/${EXECNAME}.linux:${BUILDDEP}
	mkdir -p target
	docker run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${LINUXNIMOPTS} ${NAME} && strip ${NAME} && chown ${UGID} ${NAME}"
	mv ${NAME} target/${EXECNAME}.linux
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${EXECNAME}.linux ; fi

target/${EXECNAME}.linux32:${BUILDDEP}
	mkdir -p target
	docker run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME32} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${LINUXNIMOPTS} --cpu:i386 --passC:-m32 --passL:-m32 ${NAME} && strip ${NAME} ; if [ \"$(DOCOMPRESS)\" = \"t\" ] ; then upx --best ${NAME} ; fi && chown ${UGID} ${NAME}"
	mv ${NAME} target/${EXECNAME}.linux32

target/${EXECNAME}.arm.linux:${BUILDDEP}
	mkdir -p target
	docker run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${PINIMOPTS} --cpu:arm --os:linux ${NAME} && arm-linux-gnueabi-strip ${NAME} && chown ${UGID} ${NAME}"
	mv ${NAME} target/${EXECNAME}.arm.linux
	patchelf --set-interpreter /lib/ld-linux-armhf.so.3 target/${EXECNAME}.arm.linux
	#if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${EXECNAME}.arm.linux ; fi

target/${EXECNAME}.aarch64.linux:${BUILDDEP}
	mkdir -p target
	docker run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${PINIMOPTS} --cpu:arm64 --os:linux ${NAME} && aarch64-linux-gnu-strip ${NAME} && chown ${UGID} ${NAME}"
	mv ${NAME} target/${EXECNAME}.aarch64.linux
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${EXECNAME}.aarch64.linux ; fi

target/${EXECNAME}.32.exe:${BUILDDEP}
	mkdir -p target
	docker run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${WINDOWSNIMOPTS} -d:mingw --cpu:i386  --app:${WINAPP} ${NAME} && i686-w64-mingw32-strip ${NAME}.exe && chown ${UGID} ${NAME}.exe"
	mv ${NAME}.exe target/${EXECNAME}.32.exe
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${EXECNAME}.32.exe ; fi

target/${EXECNAME}.64.exe:${BUILDDEP}
	mkdir -p target
	docker run --rm -v `pwd`:/usr/src/app -w /usr/src/app ${DOCKERNAME} bash -c "${NIMVER} nim ${COMPILER} ${BASENIMOPTS} ${WINDOWSNIMOPTS} -d:mingw --cpu:amd64 --app:${WINAPP} ${NAME} && x86_64-w64-mingw32-strip ${NAME}.exe && chown ${UGID} ${NAME}.exe"
	mv ${NAME}.exe target/${EXECNAME}.64.exe
	if [ "$(DOCOMPRESS)" = "t" ] ; then upx --best target/${EXECNAME}.64.exe ; fi


install: | all install-only

install-only:
	set -e ; mkdir -p ${DEST}/all
	set -e ; rm -rf ${DEST}/all/${EXECNAME}.* ; rm -f ${DEST}/darwin-x86_64/${EXECNAME} ${DEST}/linux-x86_64/${EXECNAME} ${DEST}/linux-i386/${EXECNAME} ${DEST}/linux-arm/${EXECNAME} ${DEST}/linux-aarch64/${EXECNAME} ${DEST}/windows-x86_64/${EXECNAME}.exe ${DEST}/windows-i686/${EXECNAME}.exe
	set -e ; if [ -f target/${EXECNAME}.osx           ] ; then mkdir -p ${DEST}/darwin-x86_64  && cp target/${EXECNAME}.osx           ${DEST}/all/ && ln -s ../all/${EXECNAME}.osx           ${DEST}/darwin-x86_64/${EXECNAME}      ; fi
	set -e ; if [ -f target/${EXECNAME}.linux         ] ; then mkdir -p ${DEST}/linux-x86_64   && cp target/${EXECNAME}.linux         ${DEST}/all/ && ln -s ../all/${EXECNAME}.linux         ${DEST}/linux-x86_64/${EXECNAME}       ; fi
	set -e ; if [ -f target/${EXECNAME}.linux32       ] ; then mkdir -p ${DEST}/linux-i386     && cp target/${EXECNAME}.linux32       ${DEST}/all/ && ln -s ../all/${EXECNAME}.linux32       ${DEST}/linux-i386/${EXECNAME}         ; fi
	set -e ; if [ -f target/${EXECNAME}.arm.linux     ] ; then mkdir -p ${DEST}/linux-arm      && cp target/${EXECNAME}.arm.linux     ${DEST}/all/ && ln -s ../all/${EXECNAME}.arm.linux     ${DEST}/linux-arm/${EXECNAME}          ; fi
	set -e ; if [ -f target/${EXECNAME}.aarch64.linux ] ; then mkdir -p ${DEST}/linux-aarch64  && cp target/${EXECNAME}.aarch64.linux ${DEST}/all/ && ln -s ../all/${EXECNAME}.aarch64.linux ${DEST}/linux-aarch64/${EXECNAME}      ; fi
	set -e ; if [ -f target/${EXECNAME}.64.exe        ] ; then mkdir -p ${DEST}/windows-x86_64 && cp target/${EXECNAME}.64.exe        ${DEST}/all/ && ln -s ../all/${EXECNAME}.64.exe        ${DEST}/windows-x86_64/${EXECNAME}.exe ; fi
	set -e ; if [ -f target/${EXECNAME}.32.exe        ] ; then mkdir -p ${DEST}/windows-i686   && cp target/${EXECNAME}.32.exe        ${DEST}/all/ && ln -s ../all/${EXECNAME}.32.exe        ${DEST}/windows-i686/${EXECNAME}.exe   ; fi

run:local
	./target/${EXECNAME} ${RUNARGS}
