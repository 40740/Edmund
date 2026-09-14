#!/bin/bash
# Assert that the built product's resource bundles are where the generated
# `Bundle.module` accessors look for them, in the shape they can read.
#
# Usage: ./scripts/verify-app-bundle.sh build/Edmund.app
#
# Called by build-app.sh on every build (local and CI) so a packaging regression
# fails the build instead of the user's first `$E=mc^2$`. See
# verify-app-bundle.swift for what is checked and why it needs Foundation to
# answer rather than a directory listing.

set -euo pipefail

APP="${1:?usage: verify-app-bundle.sh <path/to/Edmund.app>}"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$APP" ]; then
    echo "verify-app-bundle: no such app bundle: $APP" >&2
    exit 1
fi

# `swift <file>` runs the probe in interpreter mode: no build products, no
# state, ~0.1 s. Failing here aborts build-app.sh (set -e), which is the point.
exec swift "$HERE/verify-app-bundle.swift" "$APP"
