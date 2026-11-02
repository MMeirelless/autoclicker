APP_NAME = AutoClicker
BUILD_DIR = build
BUNDLE_ID = com.mmeirelless.autoclicker

.PHONY: build app run install cert quit clean

## Compile the Swift package (release).
build:
	swift build -c release

## Assemble build/AutoClicker.app (icon, Info.plist, codesign).
app:
	./scripts/build-app.sh

## Build the bundle, quit any running copy and launch the new one.
run: app quit
	open $(BUILD_DIR)/$(APP_NAME).app

## Build, quit any running copy, copy the bundle into /Applications and launch it.
install: app quit
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(BUILD_DIR)/$(APP_NAME).app /Applications/$(APP_NAME).app
	@echo "Installed /Applications/$(APP_NAME).app"
	open /Applications/$(APP_NAME).app

## Create a local signing certificate once, so rebuilds keep the Accessibility grant.
cert:
	./scripts/make-signing-cert.sh

## Quit every running copy of the app (gracefully first, so settings are saved).
quit:
	@osascript -e 'tell application id "$(BUNDLE_ID)" to quit' >/dev/null 2>&1 || true
	@sleep 1
	@pkill -f '/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)$$' 2>/dev/null || true

clean:
	rm -rf .build $(BUILD_DIR)
