.DEFAULT_GOAL := app

PROJECT := SimpleCalendar.xcodeproj
SCHEME := SimpleCalendar
CONFIGURATION ?= Release
OUTPUT_DIR ?= build/release
INSTALL_DIR ?= /Applications
SIGN_IDENTITY ?= -

OUTPUT_PATH := $(abspath $(OUTPUT_DIR))
DERIVED_DATA := $(OUTPUT_PATH)/DerivedData
APP_PATH := $(OUTPUT_PATH)/SimpleCalendar.app
DMG_PATH := $(OUTPUT_PATH)/SimpleCalendar.dmg
SIGNING := CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)"

.PHONY: app install dmg test

app:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" \
		-destination 'generic/platform=macOS' -derivedDataPath "$(DERIVED_DATA)" \
		CONFIGURATION_BUILD_DIR="$(OUTPUT_PATH)" $(SIGNING) build
	codesign --verify --strict --verbose=1 "$(APP_PATH)"

install: app
	@set -eu; \
	destination="$(INSTALL_DIR)/SimpleCalendar.app"; \
	stage=$$(mktemp -d "$(INSTALL_DIR)/.simplecalendar-install.XXXXXX"); \
	backup="$$stage/previous.app"; \
	trap 'if { [ -e "$$backup" ] || [ -L "$$backup" ]; } && [ ! -e "$$destination" ] && [ ! -L "$$destination" ]; then \
		mv "$$backup" "$$destination" || { printf "恢复旧版失败，旧版保存在 %s\n" "$$backup" >&2; exit 1; }; \
	fi; rm -rf "$$stage"' EXIT; \
	ditto "$(APP_PATH)" "$$stage/SimpleCalendar.app"; \
	codesign --verify --strict "$$stage/SimpleCalendar.app"; \
	bundle_id=$$(plutil -extract CFBundleIdentifier raw -o - "$$stage/SimpleCalendar.app/Contents/Info.plist"); \
	/usr/bin/osascript -l JavaScript \
		-e 'ObjC.import("AppKit");' \
		-e 'function run(argv) {' \
		-e '  function running() { return $$.NSRunningApplication.runningApplicationsWithBundleIdentifier(argv[0]); }' \
		-e '  const apps = running();' \
		-e '  for (let i = 0; i < apps.count; i++) { void apps.objectAtIndex(i).terminate; }' \
		-e '  for (let i = 0; i < 50 && running().count > 0; i++) { delay(0.2); }' \
		-e '  if (running().count > 0) { throw new Error("SimpleCalendar 仍在运行，安装已停止。"); }' \
		-e '}' "$$bundle_id"; \
	if [ -e "$$destination" ] || [ -L "$$destination" ]; then mv "$$destination" "$$backup"; fi; \
	mv "$$stage/SimpleCalendar.app" "$$destination"; \
	printf '已安装到 %s\n' "$$destination"

dmg: app
	@set -eu; \
	stage=$$(mktemp -d "$(OUTPUT_PATH)/.dmg-stage.XXXXXX"); \
	trap 'rm -rf "$$stage"' EXIT; \
	ditto "$(APP_PATH)" "$$stage/SimpleCalendar.app"; \
	ln -s /Applications "$$stage/Applications"; \
	hdiutil create -ov -format UDZO -volname SimpleCalendar -srcfolder "$$stage" "$(DMG_PATH)"

test:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Debug \
		-destination 'platform=macOS' -derivedDataPath "$(DERIVED_DATA)" \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- test
