APP_NAME = AutoClicker
BUILD_DIR = build

.PHONY: build app run install clean

## Compile the Swift package (release).
build:
	swift build -c release

## Assemble build/AutoClicker.app (icon, Info.plist, ad-hoc codesign).
app:
	./scripts/build-app.sh

## Build the bundle and launch it.
run: app
	open $(BUILD_DIR)/$(APP_NAME).app

## Copy the bundle into /Applications.
install: app
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(BUILD_DIR)/$(APP_NAME).app /Applications/$(APP_NAME).app
	@echo "Installed /Applications/$(APP_NAME).app"

clean:
	rm -rf .build $(BUILD_DIR)
