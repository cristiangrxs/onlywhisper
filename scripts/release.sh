#!/usr/bin/env bash
#
# Builds, signs, notarizes and publishes an OnlyWhisper release.
#
# Next release:
#   scripts/release.sh --bump-patch
#
# That raises the patch version and the Sparkle build number, commits, pushes,
# then archives, signs, notarizes and publishes. Signing and notarization use
# the defaults below. The app-specific password stays in the keychain profile.
#
# Usage:
#   scripts/release.sh [--bump-patch] [--notes path/to/notes.md] [--draft] [--skip-notarize] [--skip-sign]
#
# Defaults (override with the environment):
#   DEVELOPER_ID     Developer ID Application: Aurel-Cristian Grosu (65QU3X8PHA)
#   TEAM_ID          65QU3X8PHA
#   NOTARY_PROFILE   onlywhisper
#
# Optional environment:
#   SPARKLE_BIN      Directory containing Sparkle's sign_update tool (auto-detected from DerivedData)
#
# --bump-patch requires a clean main branch that matches origin/main.
# Without it, the current MARKETING_VERSION is released as it is.
# Sparkle compares CURRENT_PROJECT_VERSION (CFBundleVersion), so a bump always raises it.
# One-time setup: run Sparkle's generate_keys (stores the private key in the login keychain)
# and put the printed public key into the SPARKLE_PUBLIC_ED_KEY build setting.
# The notary password is stored once with `xcrun notarytool store-credentials "onlywhisper"`.
#
# --skip-sign builds an ad-hoc signed DMG and skips notarization and Sparkle.
# macOS will ask each downloader to allow the app in Privacy & Security.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="OnlyWhisper.xcodeproj"
SCHEME="OnlyWhisper"
APP_NAME="OnlyWhisper"
PBX="$ROOT/OnlyWhisper.xcodeproj/project.pbxproj"
BUILD_DIR="$ROOT/build/release"
DERIVED_DATA="$ROOT/DerivedData"
DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: Aurel-Cristian Grosu (65QU3X8PHA)}"
TEAM_ID="${TEAM_ID:-65QU3X8PHA}"
NOTARY_PROFILE="${NOTARY_PROFILE:-onlywhisper}"

NOTES_FILE=""
DRAFT_FLAG=""
SKIP_NOTARIZE=0
SKIP_SIGN=0
BUMP_PATCH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes) NOTES_FILE="$2"; shift 2 ;;
    --draft) DRAFT_FLAG="--draft"; shift ;;
    --skip-notarize) SKIP_NOTARIZE=1; shift ;;
    --skip-sign) SKIP_SIGN=1; SKIP_NOTARIZE=1; shift ;;
    --bump-patch) BUMP_PATCH=1; shift ;;
    -h|--help) sed -n '2,/^set -euo pipefail/p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

step() { printf '\n\033[1;35m==> %s\033[0m\n' "$1"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

unique_setting() {
  local key="$1"
  local values
  values="$(grep -E "${key} = " "$PBX" | sed -E "s/.*${key} = ([^;]+);/\\1/" | sort -u)"
  [[ -n "$values" && "$(printf '%s\n' "$values" | grep -c .)" -eq 1 ]] \
    || fail "${key} is missing or differs between configurations"
  printf '%s' "$values"
}

bump_patch() {
  local branch head remote marketing build major minor patch new_version new_build
  branch="$(git rev-parse --abbrev-ref HEAD)"
  [[ "$branch" == "main" ]] || fail "--bump-patch runs from main (current: ${branch})"
  [[ -z "$(git status --porcelain)" ]] || fail "Working tree is not clean. Commit or stash changes before --bump-patch."
  step "Checking origin/main"
  git fetch origin main
  head="$(git rev-parse HEAD)"
  remote="$(git rev-parse origin/main)"
  [[ "$head" == "$remote" ]] || fail "main is not in sync with origin/main"
  marketing="$(unique_setting MARKETING_VERSION)"
  build="$(unique_setting CURRENT_PROJECT_VERSION)"
  [[ "$marketing" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] \
    || fail "MARKETING_VERSION must be major.minor.patch (got ${marketing})"
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  patch="${BASH_REMATCH[3]}"
  [[ "$build" =~ ^[0-9]+$ ]] || fail "CURRENT_PROJECT_VERSION must be an integer (got ${build})"
  new_version="${major}.${minor}.$((patch + 1))"
  new_build="$((build + 1))"
  step "Bumping to ${new_version} (build ${new_build})"
  perl -i -pe "s/MARKETING_VERSION = \\Q${marketing}\\E;/MARKETING_VERSION = ${new_version};/g; s/CURRENT_PROJECT_VERSION = \\Q${build}\\E;/CURRENT_PROJECT_VERSION = ${new_build};/g" "$PBX"
  [[ "$(unique_setting MARKETING_VERSION)" == "$new_version" ]] || fail "Version bump did not apply"
  [[ "$(unique_setting CURRENT_PROJECT_VERSION)" == "$new_build" ]] || fail "Build bump did not apply"
  git add "$PBX"
  git commit -m "Bump OnlyWhisper to ${new_version}."
  git push origin HEAD
}

default_notes() {
  local previous subjects
  previous="$(git log --format=%H --grep='^Bump OnlyWhisper to ' | sed -n '2p')"
  if [[ -n "$previous" ]]; then
    subjects="$(git log --format='%s' --invert-grep --grep='^Bump OnlyWhisper to ' "${previous}..HEAD")"
  else
    subjects="$(git log --format='%s' --invert-grep --grep='^Bump OnlyWhisper to ')"
  fi
  if [[ -z "$subjects" ]]; then
    printf 'OnlyWhisper %s\n' "$VERSION"
    return
  fi
  printf 'OnlyWhisper %s\n\n' "$VERSION"
  while IFS= read -r line; do
    printf -- '- %s\n' "$line"
  done <<<"$subjects"
}

command -v gh >/dev/null || fail "GitHub CLI (gh) is not installed"
[[ -z "$NOTES_FILE" || -f "$NOTES_FILE" ]] || fail "Notes file not found: $NOTES_FILE"
if [[ $BUMP_PATCH -eq 1 ]]; then
  bump_patch
fi

step "Reading version"
SETTINGS="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -derivedDataPath "$DERIVED_DATA" -showBuildSettings 2>/dev/null)"
VERSION="$(awk -F' = ' '/ MARKETING_VERSION = / {print $2; exit}' <<<"$SETTINGS")"
BUILD="$(awk -F' = ' '/ CURRENT_PROJECT_VERSION = / {print $2; exit}' <<<"$SETTINGS")"
TAG="v$VERSION"
[[ -n "$VERSION" && -n "$BUILD" ]] || fail "Could not read MARKETING_VERSION / CURRENT_PROJECT_VERSION"
if [[ $SKIP_SIGN -eq 0 ]]; then
  grep -q ' SPARKLE_PUBLIC_ED_KEY = [^ ]' <<<"$SETTINGS" \
    || fail "SPARKLE_PUBLIC_ED_KEY is empty. Run Sparkle's generate_keys once and set the key in the target build settings."
fi
echo "Version $VERSION (build $BUILD)"

if gh release view "$TAG" >/dev/null 2>&1; then
  fail "Release $TAG already exists. Bump the version first."
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/$APP_NAME.app"
DMG="$BUILD_DIR/$APP_NAME.dmg"

if [[ $SKIP_SIGN -eq 1 ]]; then
  step "Building without Developer ID"
  xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$DERIVED_DATA" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="-" \
    ENABLE_HARDENED_RUNTIME=NO
  mkdir -p "$EXPORT_DIR"
  APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
  [[ -d "$APP" ]] || fail "Built app not found at $APP"
else
step "Archiving"
xcodebuild archive -quiet \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE" \
  -derivedDataPath "$DERIVED_DATA" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

step "Exporting with Developer ID"
cat >"$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>Developer ID Application</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -quiet \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

codesign --verify --deep --strict --verbose=2 "$APP"
fi

notarize() {
  local file="$1"
  xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$file"
}

if [[ $SKIP_NOTARIZE -eq 0 ]]; then
  step "Notarizing app"
  ditto -c -k --keepParent "$APP" "$BUILD_DIR/$APP_NAME.zip"
  xcrun notarytool submit "$BUILD_DIR/$APP_NAME.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm "$BUILD_DIR/$APP_NAME.zip"
fi

step "Creating DMG"
STAGING="$BUILD_DIR/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -ov "$DMG" >/dev/null
rm -rf "$STAGING"
if [[ $SKIP_SIGN -eq 0 ]]; then
  codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
fi

if [[ $SKIP_NOTARIZE -eq 0 ]]; then
  step "Notarizing DMG"
  notarize "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

if [[ $SKIP_SIGN -eq 0 ]]; then
  step "Signing update for Sparkle"
  if [[ -z "${SPARKLE_BIN:-}" ]]; then
    SPARKLE_BIN="$(find "$DERIVED_DATA" "$ROOT/DerivedData" -type d -path '*artifacts/sparkle/Sparkle/bin' 2>/dev/null | head -n1 || true)"
  fi
  [[ -x "${SPARKLE_BIN:-}/sign_update" ]] || fail "Sparkle sign_update not found. Set SPARKLE_BIN to Sparkle's bin directory."
  SIGNATURE_LINE="$("$SPARKLE_BIN/sign_update" "$DMG")"
  ED_SIGNATURE="$(sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/' <<<"$SIGNATURE_LINE")"
  LENGTH="$(sed -E 's/.*length="([0-9]+)".*/\1/' <<<"$SIGNATURE_LINE")"
  [[ -n "$ED_SIGNATURE" && -n "$LENGTH" ]] || fail "Could not parse sign_update output: $SIGNATURE_LINE"
fi

step "Publishing $TAG"
NOTES="$BUILD_DIR/notes.md"
if [[ -n "$NOTES_FILE" ]]; then
  cp "$NOTES_FILE" "$NOTES"
else
  default_notes >"$NOTES"
fi
if [[ $SKIP_SIGN -eq 1 ]]; then
  printf '\nThis build is not notarized. macOS asks you to allow OnlyWhisper in System Settings > Privacy & Security.\n' >>"$NOTES"
elif [[ -n "${ED_SIGNATURE:-}" ]]; then
  printf '\n<!-- sparkle:edSignature=%s length=%s build=%s -->\n' "$ED_SIGNATURE" "$LENGTH" "$BUILD" >>"$NOTES"
fi

gh release create "$TAG" "$DMG" \
  --title "$APP_NAME $VERSION" \
  --notes-file "$NOTES" \
  $DRAFT_FLAG

step "Done"
echo "Released $APP_NAME $VERSION (build $BUILD)"
echo "The website picks up the new release within about an hour."
