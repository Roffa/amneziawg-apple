# SPDX-License-Identifier: MIT
#
# Copyright (C) 2018-2019 Jason A. Donenfeld <Jason@zx2c4.com>. All Rights Reserved.

# These are generally passed to us by xcode, but we set working defaults for standalone compilation too.
ARCHS ?= x86_64 arm64
PLATFORM_NAME ?= macosx
SDKROOT ?= $(shell xcrun --sdk $(PLATFORM_NAME) --show-sdk-path)
CONFIGURATION_BUILD_DIR ?= $(CURDIR)/out
CONFIGURATION_TEMP_DIR ?= $(CURDIR)/.tmp

export PATH := $(PATH):/usr/local/bin:/opt/homebrew/bin
export CC ?= clang
export GOPATH ?= $(CONFIGURATION_TEMP_DIR)/wireguard-go-bridge/gopath
export GOMODCACHE ?= $(GOPATH)/pkg/mod
export GOCACHE ?= $(CONFIGURATION_TEMP_DIR)/wireguard-go-bridge/gocache
export GOTMPDIR ?= $(CONFIGURATION_TEMP_DIR)/wireguard-go-bridge/gotmp
LIPO ?= lipo
DESTDIR ?= $(CONFIGURATION_BUILD_DIR)
BUILDDIR ?= $(CONFIGURATION_TEMP_DIR)/wireguard-go-bridge

CFLAGS_PREFIX := $(if $(DEPLOYMENT_TARGET_CLANG_FLAG_NAME),-$(DEPLOYMENT_TARGET_CLANG_FLAG_NAME)=$($(DEPLOYMENT_TARGET_CLANG_ENV_NAME)),) -isysroot $(SDKROOT) -arch
GOARCH_arm64 := arm64
GOARCH_x86_64 := amd64
GOOS_macosx := darwin
GOOS_iphoneos := ios

build: $(DESTDIR)/libwg-go.a
version-header: $(DESTDIR)/wireguard-go-version.h

REAL_GOROOT := $(shell go env GOROOT 2>/dev/null)
export GOROOT := $(BUILDDIR)/goroot
$(GOROOT)/.prepared:
	[ -n "$(REAL_GOROOT)" ]
	mkdir -p "$(GOPATH)" "$(GOMODCACHE)" "$(GOCACHE)" "$(GOTMPDIR)"
	mkdir -p "$(GOROOT)"
	rsync -a --delete --exclude=pkg/obj/go-build "$(REAL_GOROOT)/" "$(GOROOT)/"
	chmod -R u+w "$(GOROOT)"
	mkdir -p "$(CURDIR)/.tmp/patchtmp"
	TMPDIR="$(CURDIR)/.tmp/patchtmp" patch -p1 -f -N -r- -d "$(GOROOT)" < goruntime-boottime-over-monotonic.diff
	if [ -f "$(GOROOT)/src/net/http/internal/http2/transport.go" ]; then \
		TMPDIR="$(CURDIR)/.tmp/patchtmp" patch -p1 -f -N -r- -d "$(GOROOT)" < goruntime-http2-request-body-scratch-32k.diff; \
	else \
		echo "warning: skip goruntime-http2-request-body-scratch-32k.diff because target file is missing in current Go toolchain"; \
	fi
	touch "$@"

define libwg-go-a
$(BUILDDIR)/libwg-go-$(1).a: export CGO_ENABLED := 1
$(BUILDDIR)/libwg-go-$(1).a: export CGO_CFLAGS := $(CFLAGS_PREFIX) $(ARCH)
$(BUILDDIR)/libwg-go-$(1).a: export CGO_LDFLAGS := $(CFLAGS_PREFIX) $(ARCH)
$(BUILDDIR)/libwg-go-$(1).a: export GOOS := $(GOOS_$(PLATFORM_NAME))
$(BUILDDIR)/libwg-go-$(1).a: export GOARCH := $(GOARCH_$(1))
$(BUILDDIR)/libwg-go-$(1).a: $(GOROOT)/.prepared go.mod
	go build -ldflags=-w -trimpath -v -o "$(BUILDDIR)/libwg-go-$(1).a" -buildmode c-archive
	rm -f "$(BUILDDIR)/libwg-go-$(1).h"
endef
$(foreach ARCH,$(ARCHS),$(eval $(call libwg-go-a,$(ARCH))))

$(DESTDIR)/wireguard-go-version.h: go.mod $(GOROOT)/.prepared
	@version=$$(sed -E -n 's/.*(golang\.zx2c4\.com\/wireguard|github\.com\/amnezia-vpn\/amneziawg-go\/v[0-9]+) +v([^[:space:]]+).*/\2/p' "$<" | head -n1); \
	if [ -z "$$version" ]; then version="unknown"; fi; \
	printf '#define WIREGUARD_GO_VERSION "%s"\n' "$$version" > "$@"

$(DESTDIR)/libwg-go.a: $(foreach ARCH,$(ARCHS),$(BUILDDIR)/libwg-go-$(ARCH).a)
	@mkdir -vp "$(DESTDIR)"
	$(LIPO) -create -output "$@" $^

clean:
	rm -rf "$(BUILDDIR)" "$(DESTDIR)/libwg-go.a" "$(DESTDIR)/wireguard-go-version.h"

install: build

.PHONY: clean build version-header install
