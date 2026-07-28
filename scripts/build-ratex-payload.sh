#!/bin/bash
# Build the RaTeX runtime payload — the tarball Edmund downloads when the user
# enables the "Advanced Math" extension. Bundles the `ratex-wasm` module and the
# KaTeX fonts its display list references, at the layout WasmMathHost expects:
#   ratex_wasm_bg.wasm, ratex_wasm.js, fonts/KaTeX_*.ttf
#
# Usage: ./scripts/build-ratex-payload.sh [version]
# Output: build/ratex-wasm-<version>.tar.gz  (+ prints its SHA-256 to pin in
#         RaTeXRelease.archiveSHA256). Host the tarball at RaTeXRelease.archiveURL.
set -euo pipefail

VERSION="${1:-0.1.12}"
OUT="build/ratex-wasm-${VERSION}.tar.gz"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "→ fetching ratex-wasm@${VERSION} from npm"
curl -sL "https://registry.npmjs.org/ratex-wasm/-/ratex-wasm-${VERSION}.tgz" -o "$WORK/pkg.tgz"
tar xzf "$WORK/pkg.tgz" -C "$WORK"

PAYLOAD="$WORK/payload"
mkdir -p "$PAYLOAD/fonts"
cp "$WORK/package/pkg/ratex_wasm_bg.wasm" "$PAYLOAD/"
cp "$WORK/package/pkg/ratex_wasm.js"      "$PAYLOAD/"
cp "$WORK/package/fonts/"*.ttf            "$PAYLOAD/fonts/"

mkdir -p build
# Deterministic archive so the pinned SHA-256 is independently reproducible:
# fixed mtimes, sorted entries, zeroed owner, and gzip -n (no name/timestamp).
find "$PAYLOAD" -exec touch -t 202601010000.00 {} +
( cd "$PAYLOAD" && find . -type f | LC_ALL=C sort \
    | tar --numeric-owner --uid 0 --gid 0 -cf - -T - ) \
    | gzip -n > "$OUT"

echo "→ built $OUT"
echo "   SHA-256: $(shasum -a 256 "$OUT" | awk '{print $1}')"
echo "   (paste into RaTeXRelease.archiveSHA256, host at RaTeXRelease.archiveURL)"
