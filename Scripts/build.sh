#!/bin/bash
set -euo pipefail

PRODUCT="Kanvas"
# MCP server helper bundled into Contents/MacOS/ so end users can register it from the installed
# app (/Applications/Kanvas.app/Contents/MacOS/KanvasMCP) without cloning the repo.
MCP_PRODUCT="KanvasMCP"
BUILD_DIR=".build/release"
APP_BUNDLE="${PRODUCT}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
ENTITLEMENTS="Resources/Kanvas.entitlements"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build ${PRODUCT}.app from Swift Package

Options:
  --clean       Clean build artifacts before building
  --test        Run tests before building
  --install     Install to /Applications after building
  --no-sign     Skip code signing
  -h, --help    Show this help
EOF
}

DO_CLEAN=false
DO_TEST=false
DO_INSTALL=false
NO_SIGN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)     DO_CLEAN=true;  shift ;;
        --test)      DO_TEST=true;   shift ;;
        --install)   DO_INSTALL=true; shift ;;
        --no-sign)   NO_SIGN=true; shift ;;
        -h|--help)   usage; exit 0 ;;
        *) error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

cd "${PROJECT_DIR}"

if ${DO_CLEAN}; then
    info "Cleaning build artifacts..."
    swift package clean
    rm -rf "${APP_BUNDLE}"
fi

if ${DO_TEST}; then
    info "Running tests..."
    swift test
fi

info "Building ${PRODUCT} (release)..."
swift build -c release

info "Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS}" "${RESOURCES}"
cp "${BUILD_DIR}/${PRODUCT}" "${MACOS}/"
cp "${BUILD_DIR}/${MCP_PRODUCT}" "${MACOS}/"
cp Resources/Info.plist "${CONTENTS}/"

# Generate the Dock/Finder icon from the source artwork. The script warns and
# continues if Resources/AppIconSource.png is absent (bundle uses default icon).
# Plain `swift build` does NOT stamp the icon — only this bundle step does.
info "Generating app icon..."
swift "${SCRIPT_DIR}/generate_icon.swift" \
    "Resources/AppIconSource.png" \
    "${RESOURCES}/AppIcon.icns"

if ! ${NO_SIGN}; then
    info "Code signing ${APP_BUNDLE}..."
    IDENTITY=$(security find-identity -v -p codesigning | head -1 | sed -E 's/.*"(.*)"/\1/')
    if [[ -n "${IDENTITY}" && "${IDENTITY}" != *"0 valid"* ]]; then
        # Sign the nested MCP helper first (inside-out), then the bundle — signing the bundle
        # does not re-sign nested executables. The helper needs no app entitlements.
        codesign --force --sign "${IDENTITY}" \
            --options runtime \
            "${MACOS}/${MCP_PRODUCT}"
        codesign --force --sign "${IDENTITY}" \
            --entitlements "${ENTITLEMENTS}" \
            --options runtime \
            "${APP_BUNDLE}"
        info "Signed with: ${IDENTITY}"
    else
        warn "No signing identity found; using ad-hoc signature"
        codesign --force --sign - "${MACOS}/${MCP_PRODUCT}"
        codesign --force --sign - \
            --entitlements "${ENTITLEMENTS}" \
            "${APP_BUNDLE}"
        info "Signed with ad-hoc identity"
    fi
fi

if ${DO_INSTALL}; then
    if pgrep -f "${PRODUCT}.app/Contents/MacOS/${PRODUCT}" > /dev/null 2>&1; then
        info "Stopping running ${PRODUCT}..."
        pkill -f "${PRODUCT}.app/Contents/MacOS/${PRODUCT}" || true
        sleep 0.5
    fi
    info "Installing to /Applications..."
    rm -rf "/Applications/${APP_BUNDLE}"
    cp -R "${APP_BUNDLE}" /Applications/
    info "Installed to /Applications/${APP_BUNDLE}"
fi

info "Built ${APP_BUNDLE}"
