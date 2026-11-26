.DEFAULT_GOAL := app

PROJECT := SimpleCalendar.xcodeproj
SCHEME := SimpleCalendar
APP_NAME := Calendar
CONFIGURATION ?= Release
OUTPUT_DIR ?= build/release
INSTALL_DIR ?= /Applications
SIGN_IDENTITY ?= -

OUTPUT_PATH := $(abspath $(OUTPUT_DIR))
DERIVED_DATA := $(OUTPUT_PATH)/DerivedData
APP_PATH := $(OUTPUT_PATH)/$(APP_NAME).app
DMG_PATH := $(OUTPUT_PATH)/$(APP_NAME).dmg
SIGNING := CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)"

.PHONY: app install dmg test

app:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration "$(CONFIGURATION)" \
		-destination 'generic/platform=macOS' -derivedDataPath "$(DERIVED_DATA)" \
		CONFIGURATION_BUILD_DIR="$(OUTPUT_PATH)" $(SIGNING) build
	codesign --verify --strict --verbose=1 "$(APP_PATH)"

install: app
	@set -eu; \
	destination="$(INSTALL_DIR)/$(APP_NAME).app"; \
	stage=$$(mktemp -d "$(INSTALL_DIR)/.calendar-install.XXXXXX"); \
	staged="$$stage/$(APP_NAME).app"; \
	backup="$$stage/previous.app"; \
	installed=0; \
	trap 'if [ "$$installed" -eq 0 ] && [ -e "$$backup" ]; then \
		if [ -e "$$destination" ] || [ -L "$$destination" ] || ! mv "$$backup" "$$destination"; then \
			printf "恢复旧版失败，旧版保存在 %s\n" "$$backup" >&2; exit 1; \
		fi; \
	fi; rm -rf "$$stage"' EXIT; \
	ditto "$(APP_PATH)" "$$staged"; \
	codesign --verify --strict "$$staged"; \
	bundle_id=$$(plutil -extract CFBundleIdentifier raw -o - "$$staged/Contents/Info.plist"); \
	if [ -e "$$destination" ] || [ -L "$$destination" ]; then \
		if [ -L "$$destination" ] || [ "$$(plutil -extract CFBundleIdentifier raw -o - "$$destination/Contents/Info.plist" 2>/dev/null || true)" != "$$bundle_id" ]; then \
			printf '安装路径已被其他应用占用：%s\n' "$$destination" >&2; exit 1; \
		fi; \
	fi; \
	/usr/bin/osascript -l JavaScript \
		-e 'ObjC.import("AppKit");' \
		-e 'function run(argv) {' \
		-e '  function running() { return $$.NSRunningApplication.runningApplicationsWithBundleIdentifier(argv[0]); }' \
		-e '  const apps = running();' \
		-e '  for (let i = 0; i < apps.count; i++) { void apps.objectAtIndex(i).terminate; }' \
		-e '  for (let i = 0; i < 50 && running().count > 0; i++) { delay(0.2); }' \
		-e '  if (running().count > 0) { throw new Error("Calendar 仍在运行，安装已停止。"); }' \
		-e '}' "$$bundle_id"; \
	if [ -e "$$destination" ]; then mv "$$destination" "$$backup"; fi; \
	mv "$$staged" "$$destination"; \
	installed=1; \
	printf '已安装到 %s\n' "$$destination"; \
	if ! /usr/bin/open "$$destination"; then \
		printf 'Calendar 已安装，启动失败：%s\n' "$$destination" >&2; exit 1; \
	fi

dmg: app
	@set -eu; \
	stage=$$(mktemp -d "$(OUTPUT_PATH)/.dmg-stage.XXXXXX"); \
	trap 'rm -rf "$$stage"' EXIT; \
	ditto "$(APP_PATH)" "$$stage/$(APP_NAME).app"; \
	ln -s /Applications "$$stage/Applications"; \
	hdiutil create -ov -format UDZO -volname "$(APP_NAME)" -srcfolder "$$stage" "$(DMG_PATH)"

test:
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Debug \
		-destination 'platform=macOS' -derivedDataPath "$(DERIVED_DATA)" \
		CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- test
