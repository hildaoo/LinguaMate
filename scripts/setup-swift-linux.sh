#!/usr/bin/env bash
set -euo pipefail

# Installs a signature-verified, fixed toolchain outside the repository.
# macOS developers should use Xcode's Swift instead.
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo 'This helper requires Linux x86_64; on macOS use Xcode.' >&2
  exit 1
fi
toolchain_root="${LINGUAMATE_TOOLCHAIN_ROOT:-/workspace/toolchains}"
swift_release='swift-6.0.3-RELEASE-ubuntu24.04'
if [[ -x "$toolchain_root/$swift_release/usr/bin/swift" ]]; then
  "$toolchain_root/$swift_release/usr/bin/swift" --version
  exit 0
fi
mkdir -p "$toolchain_root"
download_dir="$(mktemp -d)"
trap 'rm -rf "$download_dir"' EXIT
release_url="https://download.swift.org/swift-6.0.3-release/ubuntu2404/swift-6.0.3-RELEASE/$swift_release.tar.gz"
curl --fail --location --proto '=https' --tlsv1.2 "$release_url" -o "$download_dir/swift.tar.gz"
curl --fail --location --proto '=https' --tlsv1.2 "$release_url.sig" -o "$download_dir/swift.tar.gz.sig"
curl --fail --location --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/swiftlang/swift-org-website/main/keys/all-keys.asc -o "$download_dir/keys.asc"
mkdir -m 700 "$download_dir/gnupg"
gpg --homedir "$download_dir/gnupg" --batch --import "$download_dir/keys.asc"
gpg --homedir "$download_dir/gnupg" --batch --status-fd 1 --verify "$download_dir/swift.tar.gz.sig" "$download_dir/swift.tar.gz" > "$download_dir/signature-status"
if ! grep -q 'VALIDSIG 52BB7E3DE28A71BE22EC05FFEF80A866B47A981F ' "$download_dir/signature-status"; then
  echo 'The Swift 6 release signature did not match the expected official signing key.' >&2
  exit 1
fi
tar -xzf "$download_dir/swift.tar.gz" -C "$toolchain_root"
"$toolchain_root/$swift_release/usr/bin/swift" --version
