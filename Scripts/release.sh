#!/bin/bash
set -euo pipefail

# Build a Developer ID-signed, notarized, stapled DMG of Kanvas.app, ready to
# attach to a GitHub release and reference from a Homebrew Cask.
#
# Prerequisites (one-time):
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. A notarytool keychain profile. Create it once with:
#        xcrun notarytool store-credentials "$NOTARY_PROFILE" \
#          --apple-id "<your-apple-id>" \
#          --team-id  "<your-team-id>" \
#          --password "<app-specific-password>"
#      (App-specific password: https://account.apple.com → Sign-In and Security)
#
# Environment overrides:
#   SIGN_IDENTITY   Code-signing identity (default: auto-detected Developer ID Application)
#   NOTARY_PROFILE  notarytool keychain profile name (default: kanvas-notary)
#   SKIP_NOTARIZE   "true" to build+sign+DMG but skip notarization (local smoke test)

PRODUCT="Kanvas"
MCP_PRODUCT="KanvasMCP"
APP_BUNDLE="${PRODUCT}.app"
MACOS="${APP_BUNDLE}/Contents/MacOS"
ENTITLEMENTS="Resources/Kanvas.entitlements"
NOTARY_PROFILE="${NOTARY_PROFILE:-kanvas-notary}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-false}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; }

cd "${PROJECT_DIR}"

# --- Resolve signing identity ----------------------------------------------
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning \
        | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')
fi
if [[ -z "${SIGN_IDENTITY}" ]]; then
    error "No 'Developer ID Application' identity found. Set SIGN_IDENTITY or install the certificate."
    exit 1
fi
info "Signing identity: ${SIGN_IDENTITY}"

# --- Version from Info.plist -----------------------------------------------
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG_NAME="${PRODUCT}-${VERSION}.dmg"
info "Building ${PRODUCT} ${VERSION}"

# --- Build the unsigned bundle, then sign with Developer ID -----------------
info "Building release bundle (unsigned)..."
"${SCRIPT_DIR}/build.sh" --clean --no-sign

# Sign the nested MCP helper first (inside-out), then the bundle — signing the
# bundle does not re-sign nested executables. The helper needs no app entitlements.
info "Signing nested ${MCP_PRODUCT} with Developer ID + hardened runtime..."
codesign --force --sign "${SIGN_IDENTITY}" \
    --options runtime \
    --timestamp \
    "${MACOS}/${MCP_PRODUCT}"

info "Signing ${APP_BUNDLE} with Developer ID + hardened runtime..."
codesign --force --sign "${SIGN_IDENTITY}" \
    --entitlements "${ENTITLEMENTS}" \
    --options runtime \
    --timestamp \
    "${APP_BUNDLE}"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
info "Code signature verified."

make_dmg() {
    local stage
    stage="$(mktemp -d)"
    cp -R "${APP_BUNDLE}" "${stage}/"
    ln -s /Applications "${stage}/Applications"
    rm -f "${DMG_NAME}"
    hdiutil create \
        -volname "${PRODUCT}" \
        -srcfolder "${stage}" \
        -fs HFS+ \
        -format UDZO \
        "${DMG_NAME}" >/dev/null
    rm -rf "${stage}"
}

notarize_dmg() {
    xcrun notarytool submit "${DMG_NAME}" --keychain-profile "${NOTARY_PROFILE}" --wait
}

# --- Assemble + notarize + staple -------------------------------------------
# Two notarization passes so that BOTH the DMG and the .app inside it carry a
# stapled ticket (the app's ticket only becomes fetchable after the first pass,
# and stapling the app changes the DMG's hash, so the rebuilt DMG must be
# notarized again). This lets the extracted app pass Gatekeeper even offline.
if [[ "${SKIP_NOTARIZE}" == "true" ]]; then
    warn "SKIP_NOTARIZE=true — skipping notarization. DMG will trip Gatekeeper."
    info "Creating ${DMG_NAME}..."
    make_dmg
else
    info "Creating ${DMG_NAME} (pass 1/2)..."
    make_dmg
    info "Notarizing to register the app ticket (pass 1/2)..."
    notarize_dmg
    info "Stapling the .app..."
    xcrun stapler staple "${APP_BUNDLE}"
    info "Rebuilding ${DMG_NAME} with the stapled app (pass 2/2)..."
    make_dmg
    info "Notarizing the final DMG (pass 2/2)..."
    notarize_dmg
    info "Stapling the DMG..."
    xcrun stapler staple "${DMG_NAME}"
    xcrun stapler validate "${DMG_NAME}"
    spctl -a -vvv -t exec "${APP_BUNDLE}" || true
fi

# --- Report -----------------------------------------------------------------
SHA256=$(shasum -a 256 "${DMG_NAME}" | awk '{print $1}')
info "Done."
echo
echo "  Artifact : ${PROJECT_DIR}/${DMG_NAME}"
echo "  Version  : ${VERSION}"
echo "  sha256   : ${SHA256}"
echo
echo "Next steps:"
echo "  1. Create a GitHub release tagged v${VERSION} and upload ${DMG_NAME}."
echo "  2. Update packaging/homebrew/kanvas.rb: version \"${VERSION}\", sha256 \"${SHA256}\"."
echo "  3. Copy it into the s-age/homebrew-kanvas repo at Casks/kanvas.rb."
