APP_NAME := Voice2Input
APP_BUNDLE := build/$(APP_NAME).app

.PHONY: build run install clean setup-signing

setup-signing:
	./scripts/create_local_codesign_identity.sh

build:
	./scripts/build_app.sh release

run:
	./scripts/build_app.sh debug
	open "$(APP_BUNDLE)"

install: build
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/$(APP_NAME).app"
	ditto "$(APP_BUNDLE)" "$(HOME)/Applications/$(APP_NAME).app"

clean:
	rm -rf .build build
