#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${HSTRACKER_BUILD_ROOT:-$ROOT/build/local}"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
SOURCE_PACKAGES="$BUILD_ROOT/SourcePackages"
ARTIFACT_DIR="$BUILD_ROOT/artifacts"
PREVIOUS_DIR="$BUILD_ROOT/previous"
APP_NAME="HSTracker Arena.app"
BUNDLE_ID="io.github.serge-ml.hstrackerarena"
ENTITLEMENTS="$ROOT/HSTracker/HSTracker.entitlements"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
ARTIFACT_APP="$ARTIFACT_DIR/$APP_NAME"
PREVIOUS_APP="$PREVIOUS_DIR/$APP_NAME"
INSTALL_DIR="${HSTRACKER_INSTALL_DIR:-/Applications}"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME"

log() {
    printf '[HSTracker Arena] %s\n' "$*"
}

fail() {
    printf '[HSTracker Arena] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  scripts/hstracker_arena_app.sh build
  scripts/hstracker_arena_app.sh install [--no-build]
  scripts/hstracker_arena_app.sh rollback
  scripts/hstracker_arena_app.sh launch
  scripts/hstracker_arena_app.sh status

Environment:
  HSTRACKER_BUILD_ROOT          Persistent build directory (default: build/local)
  HSTRACKER_INSTALL_DIR         App destination (default: /Applications)
  HSTRACKER_SIGNING_IDENTITY    codesign identity; "-" forces local ad-hoc signing
EOF
}

bundle_value() {
    /usr/libexec/PlistBuddy -c "Print:$2" "$1/Contents/Info.plist"
}

verify_app() {
    local app="$1"
    local entitlement

    test -d "$app" || fail "App bundle not found: $app"
    test -s "$ENTITLEMENTS" || fail "Signing entitlements are missing: $ENTITLEMENTS"
    test "$(bundle_value "$app" CFBundleIdentifier)" = "$BUNDLE_ID" ||
        fail "Unexpected bundle identifier in $app"
    test -s "$app/Contents/Resources/Resources/Cards/CardDefs.xml" ||
        fail "CardDefs.xml is missing from $app"
    test -s "$app/Contents/Resources/Resources/Managed/BobsBuddy.dll" ||
        fail "BobsBuddy.dll is missing from $app"
    test -s "$app/Contents/Resources/Resources/Managed/arm64/System.Private.CoreLib.dll" ||
        fail "The arm64 Mono runtime is missing from $app"
    test -s "$app/Contents/Resources/Resources/Managed/x64/System.Private.CoreLib.dll" ||
        fail "The x64 Mono runtime is missing from $app"
    codesign --verify --deep --strict "$app"
    for entitlement in \
        com.apple.security.cs.allow-dyld-environment-variables \
        com.apple.security.cs.allow-jit \
        com.apple.security.cs.debugger \
        com.apple.security.cs.disable-library-validation
    do
        codesign -d --entitlements - "$app" 2>/dev/null |
            grep -q "$entitlement" ||
            fail "Required entitlement is missing from $app: $entitlement"
    done
}

detect_signing_identity() {
    if [ -n "${HSTRACKER_SIGNING_IDENTITY:-}" ]; then
        printf '%s' "$HSTRACKER_SIGNING_IDENTITY"
        return
    fi

    local identity
    identity="$(
        security find-identity -v -p codesigning 2>/dev/null |
            awk -F'"' '/^[[:space:]]*[0-9]+\)/ { print $2; exit }'
    )"
    printf '%s' "${identity:--}"
}

sign_app() {
    local app="$1"
    local identity
    identity="$(detect_signing_identity)"

    if [ "$identity" = "-" ]; then
        log "Signing locally with a stable ad-hoc designated requirement"
        codesign \
            --force \
            --deep \
            --sign - \
            --timestamp=none \
            "$app"
        codesign \
            --force \
            --sign - \
            --timestamp=none \
            --options runtime \
            --entitlements "$ENTITLEMENTS" \
            --requirements "=designated => identifier \"$BUNDLE_ID\"" \
            "$app"
    else
        log "Signing with identity: $identity"
        codesign \
            --force \
            --deep \
            --sign "$identity" \
            --timestamp=none \
            "$app"
        codesign \
            --force \
            --sign "$identity" \
            --timestamp=none \
            --options runtime \
            --entitlements "$ENTITLEMENTS" \
            "$app"
    fi
}

build_app() {
    mkdir -p "$BUILD_ROOT" "$DERIVED_DATA" "$SOURCE_PACKAGES" "$ARTIFACT_DIR"

    log "Resolving Swift packages into $SOURCE_PACKAGES"
    xcodebuild \
        -resolvePackageDependencies \
        -project "$ROOT/HSTracker.xcodeproj" \
        -clonedSourcePackagesDirPath "$SOURCE_PACKAGES"

    log "Building the unsigned Release app"
    xcodebuild build \
        -quiet \
        -project "$ROOT/HSTracker.xcodeproj" \
        -scheme HSTracker \
        -configuration Release \
        -destination "platform=macOS" \
        -derivedDataPath "$DERIVED_DATA" \
        -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" \
        -disableAutomaticPackageResolution \
        CODE_SIGNING_ALLOWED=NO

    test -d "$BUILT_APP" || fail "Xcode did not produce $BUILT_APP"
    rm -rf "$ARTIFACT_APP"
    ditto "$BUILT_APP" "$ARTIFACT_APP"
    sign_app "$ARTIFACT_APP"
    verify_app "$ARTIFACT_APP"

    log "Release artifact ready: $ARTIFACT_APP"
}

quit_installed_app() {
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" \
        >/dev/null 2>&1 || true

    local executable="$INSTALLED_APP/Contents/MacOS/HSTracker Arena"
    local attempt
    for attempt in $(seq 1 40); do
        if ! pgrep -f "$executable" >/dev/null 2>&1; then
            return
        fi
        sleep 0.25
    done
    fail "The installed app is still running; quit it and retry"
}

install_artifact() {
    verify_app "$ARTIFACT_APP"
    test -d "$INSTALL_DIR" || fail "Install directory does not exist: $INSTALL_DIR"
    test -w "$INSTALL_DIR" || fail "Install directory is not writable: $INSTALL_DIR"

    quit_installed_app

    local incoming="$INSTALL_DIR/.HSTracker Arena.installing.$$.app"
    local previous_moved=0
    rm -rf "$incoming"
    ditto "$ARTIFACT_APP" "$incoming"
    verify_app "$incoming"

    mkdir -p "$PREVIOUS_DIR"
    if [ -d "$INSTALLED_APP" ]; then
        rm -rf "$PREVIOUS_APP"
        mv "$INSTALLED_APP" "$PREVIOUS_APP"
        previous_moved=1
    fi

    if ! mv "$incoming" "$INSTALLED_APP"; then
        if [ "$previous_moved" -eq 1 ] && [ ! -e "$INSTALLED_APP" ]; then
            mv "$PREVIOUS_APP" "$INSTALLED_APP"
        fi
        fail "Atomic install failed; the previous app was restored"
    fi

    verify_app "$INSTALLED_APP"
    log "Installed: $INSTALLED_APP"
    if [ "$previous_moved" -eq 1 ]; then
        log "Rollback copy: $PREVIOUS_APP"
    fi
}

rollback_app() {
    test -d "$PREVIOUS_APP" ||
        fail "No previous local installation is available"
    verify_app "$PREVIOUS_APP"
    quit_installed_app

    local current="$BUILD_ROOT/.rollback-current.$$.app"
    rm -rf "$current"
    if [ -d "$INSTALLED_APP" ]; then
        mv "$INSTALLED_APP" "$current"
    fi

    if ! mv "$PREVIOUS_APP" "$INSTALLED_APP"; then
        if [ -d "$current" ]; then
            mv "$current" "$INSTALLED_APP"
        fi
        fail "Rollback failed; the current app was restored"
    fi

    if [ -d "$current" ]; then
        mv "$current" "$PREVIOUS_APP"
    fi
    verify_app "$INSTALLED_APP"
    log "Rollback completed"
}

launch_app() {
    verify_app "$INSTALLED_APP"
    open "$INSTALLED_APP"
    log "Launched: $INSTALLED_APP"
}

status_app() {
    printf 'Build root: %s\n' "$BUILD_ROOT"
    printf 'Artifact:   %s\n' "$ARTIFACT_APP"
    printf 'Installed:  %s\n' "$INSTALLED_APP"
    printf 'Previous:   %s\n' "$PREVIOUS_APP"

    if [ -d "$INSTALLED_APP" ]; then
        verify_app "$INSTALLED_APP"
        printf 'Version:    %s (%s)\n' \
            "$(bundle_value "$INSTALLED_APP" CFBundleShortVersionString)" \
            "$(bundle_value "$INSTALLED_APP" CFBundleVersion)"
        codesign -d -r- --verbose=2 "$INSTALLED_APP" 2>&1 |
            tail -n 1
    else
        printf 'State:      not installed\n'
    fi

    if [ -d "$PREVIOUS_APP" ]; then
        printf 'Rollback:   available, version %s (%s)\n' \
            "$(bundle_value "$PREVIOUS_APP" CFBundleShortVersionString)" \
            "$(bundle_value "$PREVIOUS_APP" CFBundleVersion)"
    else
        printf 'Rollback:   not available\n'
    fi
}

command="${1:-}"
case "$command" in
    build)
        build_app
        ;;
    install)
        if [ "${2:-}" != "--no-build" ]; then
            build_app
        fi
        install_artifact
        launch_app
        ;;
    rollback)
        rollback_app
        launch_app
        ;;
    launch)
        launch_app
        ;;
    status)
        status_app
        ;;
    *)
        usage
        exit 2
        ;;
esac
