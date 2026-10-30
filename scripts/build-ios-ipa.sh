#!/usr/bin/env bash
# Build a device IPA for the owner to sign locally with their own Apple account.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Building an iPhone IPA requires macOS and Xcode.' >&2
  exit 1
fi
output_dir="${1:?Usage: bash scripts/build-ios-ipa.sh OUTPUT_DIRECTORY}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/linguamate-ios.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

xcodebuild -project ios/LinguaMate.xcodeproj -scheme LinguaMate \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$build_dir/DerivedData" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build

app="$build_dir/DerivedData/Build/Products/Release-iphoneos/LinguaMate.app"
plist="$app/Info.plist"
platform="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$plist")"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
if [[ "$platform" != iPhoneOS || "$(xcrun lipo -archs "$app/$executable")" != arm64 ]]; then
  echo 'Expected an arm64 iPhone device build.' >&2
  exit 1
fi

mkdir -p "$build_dir/package/Payload"
ditto "$app" "$build_dir/package/Payload/LinguaMate.app"
ipa="LinguaMate-$version-unsigned.ipa"
# Replace a previous archive instead of leaving old ZIP entries in an updated build.
rm -f "$output_dir/$ipa"
(cd "$build_dir/package" && /usr/bin/zip -qry "$output_dir/$ipa" Payload)
unzip -tq "$output_dir/$ipa"
(cd "$output_dir" && shasum -a 256 "$ipa" > SHA256SUMS.txt)
cp docs/install-windows.md "$output_dir/安装说明.md"
{
  echo 'Unsigned arm64 iPhone device build; sign on your own computer before installation.'
  echo "Source commit: $(git rev-parse HEAD)"
  echo "Version: $version"
  echo "iOS SDK: $(xcrun --sdk iphoneos --show-sdk-version)"
  xcodebuild -version
} > "$output_dir/build-info.txt"
echo "Device IPA prepared: $output_dir/$ipa"
