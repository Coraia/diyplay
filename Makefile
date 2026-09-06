PREFIX ?= $(HOME)/Applications
APP = $(PREFIX)/Diyplay.app

.PHONY: all build app install doctor

all: app

build:
	swift build -c release

app: build
	rm -rf dist/Diyplay.app
	mkdir -p dist/Diyplay.app/Contents/MacOS
	cp .build/release/diyplay dist/Diyplay.app/Contents/MacOS/diyplay
	cp app/Info.plist dist/Diyplay.app/Contents/Info.plist
	mkdir -p dist/Diyplay.app/Contents/Resources
	cp app/AppIcon.icns dist/Diyplay.app/Contents/Resources/AppIcon.icns

install: app
	mkdir -p "$(PREFIX)"
	rm -rf "$(APP)"
	cp -R dist/Diyplay.app "$(APP)"
	./scripts/install-override.sh
	open "$(APP)"

doctor:
	./.build/release/diyplay doctor
