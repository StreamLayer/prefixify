#!/usr/bin/xcrun make -f

SLR_TEMPORARY_FOLDER?=/tmp/SLR.dst
PREFIX?=/usr/local
CONFIGURATION?=release

INTERNAL_PACKAGE=SLRApp.pkg
OUTPUT_PACKAGE=SLR.pkg

SLR_EXECUTABLE=./.build/$(CONFIGURATION)/swift-prefixify
BINARIES_FOLDER=/usr/local/bin

SWIFT_BUILD_FLAGS=--configuration $(CONFIGURATION)

SWIFTPM_DISABLE_SANDBOX_SHOULD_BE_FLAGGED:=$(shell test -n "$${HOMEBREW_SDKROOT}" && echo should_be_flagged)
ifeq ($(SWIFTPM_DISABLE_SANDBOX_SHOULD_BE_FLAGGED), should_be_flagged)
SWIFT_BUILD_FLAGS+= --disable-sandbox
endif
SWIFT_STATIC_STDLIB_SHOULD_BE_FLAGGED:=$(shell test -d $$(dirname $$(xcrun --find swift))/../lib/swift_static/macosx && echo should_be_flagged)
ifeq ($(SWIFT_STATIC_STDLIB_SHOULD_BE_FLAGGED), should_be_flagged)
SWIFT_BUILD_FLAGS+= -Xswiftc -static-stdlib
endif

# ZSH_COMMAND · run single command in `zsh` shell, ignoring most `zsh` startup files.
ZSH_COMMAND := ZDOTDIR='/var/empty' zsh -o NO_GLOBAL_RCS -c
# RM_SAFELY · `rm -rf` ensuring first and only parameter is non-null, contains more than whitespace, non-root if resolving absolutely.
# RM_SAFELY := $(ZSH_COMMAND) '[[ ! $${1:?} =~ "^[[:space:]]+\$$" ]] && [[ $${1:A} != "/" ]] && [[ $${\#} == "1" ]] && noglob rm -rf $${1:A}' --

VERSION_STRING=$(shell git describe --abbrev=0 --tags)
DISTRIBUTION_PLIST=Sources/Distribution.plist

TEST_FILTER:=

RM=rm -f
MKDIR=mkdir -p
SUDO=sudo
CP=cp

.PHONY: all clean install package uninstall xcconfig xcodeproj

all: installables

clean:
	swift package clean

installables:
	swift build $(SWIFT_BUILD_FLAGS)

package: installables
	$(MKDIR) "$(SLR_TEMPORARY_FOLDER)$(BINARIES_FOLDER)"
	$(CP) "$(SLR_EXECUTABLE)" "$(SLR_TEMPORARY_FOLDER)$(BINARIES_FOLDER)"

	pkgbuild \
		--identifier "com.streamlayer.prefixify" \
		--install-location "/" \
		--root "$(SLR_TEMPORARY_FOLDER)" \
		--version "$(VERSION_STRING)" \
		"$(INTERNAL_PACKAGE)"

	productbuild \
	  	--distribution "$(DISTRIBUTION_PLIST)" \
	  	--package-path "$(INTERNAL_PACKAGE)" \
	   	"$(OUTPUT_PACKAGE)"

prefix_install: installables
	$(MKDIR) "$(PREFIX)/bin"
	$(CP) -f "$(SLR_EXECUTABLE)" "$(PREFIX)/bin/"

install: installables
	$(SUDO) $(CP) -f "$(SLR_EXECUTABLE)" "$(BINARIES_FOLDER)"

uninstall:
	$(RM) "$(BINARIES_FOLDER)/swift-prefixify"

.build/libSwiftPM.xcconfig:
	mkdir -p .build
	echo "OTHER_CFLAGS = -DSWIFT_PACKAGE" >> "$@"

xcconfig: .build/libSwiftPM.xcconfig

xcodeproj: xcconfig
	 swift package generate-xcodeproj --xcconfig-overrides .build/libSwiftPM.xcconfig
