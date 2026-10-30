#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${LINGUAMATE_TOOLCHAIN_ROOT:-}" ]]; then
  swift_binary="$LINGUAMATE_TOOLCHAIN_ROOT/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/swift"
elif command -v swift >/dev/null 2>&1; then
  swift_binary="$(command -v swift)"
else
  swift_binary="${LINGUAMATE_TOOLCHAIN_ROOT:-/workspace/toolchains}/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin/swift"
fi
cache_root="${LINGUAMATE_CACHE_ROOT:-$PWD/.build/local-cache}"
mkdir -p "$cache_root"
export CLANG_MODULE_CACHE_PATH="$cache_root/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$cache_root/modules"
"$swift_binary" test --jobs 4 --cache-path "$cache_root/swiftpm" --config-path "$cache_root/config" --security-path "$cache_root/security" "$@"
