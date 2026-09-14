#!/bin/bash
# Build Edmund.app — a standalone macOS application bundle.
# Usage: ./scripts/build-app.sh
# Output: build/Edmund.app (ready to drag into /Applications)

set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Edmund"
BUNDLE="build/${APP_NAME}.app"
# The executable target is "edmd" (see Package.swift); the binary keeps that name
# inside the bundle even though the app presents as "Edmund".
EXECUTABLE="edmd"

echo "Building release binary..."
# Keep the last lines on success, but dump the *whole* log when the build fails
# — `| tail -3` used to swallow every diagnostic, leaving a release run failing
# with nothing but "exit code 1" in the CI log.
BUILD_LOG="$(mktemp)"
if ! swift build -c release >"$BUILD_LOG" 2>&1; then
    echo "swift build failed — full log:"
    cat "$BUILD_LOG"
    rm -f "$BUILD_LOG"
    exit 1
fi
tail -3 "$BUILD_LOG"
rm -f "$BUILD_LOG"

echo "Creating ${APP_NAME}.app bundle..."
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"

cp ".build/release/${EXECUTABLE}" "${BUNDLE}/Contents/MacOS/${EXECUTABLE}"
cp Info.plist "${BUNDLE}/Contents/"
cp Resources/AppIcon.icns "${BUNDLE}/Contents/Resources/AppIcon.icns"

# Compile the asset catalog so the app's AccentColor (our brown) is available.
# macOS uses it only when the user's system accent is "Multicolor"; a specific
# system accent still wins, which is the behavior we want.
# `actool` ships with full Xcode, not the Command Line Tools, so fall back to
# Xcode.app's copy when xcode-select points at the CLT.
echo "Compiling asset catalog..."
ACTOOL="$(xcrun --find actool 2>/dev/null || echo /Applications/Xcode.app/Contents/Developer/usr/bin/actool)"
"$ACTOOL" Resources/Assets.xcassets \
    --compile "${BUNDLE}/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --output-partial-info-plist "$(mktemp)" \
    >/dev/null

# Generate the App Intents metadata bundle (Metadata.appintents) that Shortcuts
# and Spotlight read to discover the intents in Intents.swift.
#
# KNOWN LIMITATION: appintentsmetadataprocessor needs per-file .swiftconstvalues
# supplementary outputs from the Swift compiler (it fails otherwise with
# "No swift const values found … BinaryScanningError error 6"). Xcode's build
# system requests those outputs via SWIFT_ENABLE_EMIT_CONST_VALUES; SwiftPM has
# no equivalent — passing -const-gather-protocols-file alone does not populate
# the output-file-map with const-values entries, so nothing is emitted. Until
# SwiftPM supports it (or the app is built from an Xcode project), the metadata
# bundle can't be produced here. The intents still compile and are correct; they
# simply won't appear in Shortcuts from a SwiftPM-built app. The Services-menu
# entries (Info.plist NSServices) provide the same "Open in Edmund" / "New
# Document with Selection" actions with no metadata dependency.
#
# The step below is left in, best-effort: it succeeds automatically the day the
# toolchain can emit the const values, and is a no-op warning until then.
echo "Generating App Intents metadata..."
AIMP="$(xcrun --find appintentsmetadataprocessor 2>/dev/null \
    || echo /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsmetadataprocessor)"
CONST_LIST="$(find .build/release -name '*.swiftconstvalues' 2>/dev/null | head -1 || true)"
if [ -x "$AIMP" ] && [ -n "$CONST_LIST" ]; then
    TOOLCHAIN_DIR="$(dirname "$(dirname "$(dirname "$AIMP")")")"
    CONST_FILELIST="$(mktemp)"
    find .build/release -name '*.swiftconstvalues' > "$CONST_FILELIST"
    "$AIMP" \
        --output "${BUNDLE}/Contents/Resources" \
        --module-name edmd \
        --target-triple "$(uname -m)-apple-macos14.0" \
        --toolchain-dir "$TOOLCHAIN_DIR" \
        --sdk-root "$(xcrun --show-sdk-path)" \
        --binary-file "${BUNDLE}/Contents/MacOS/${EXECUTABLE}" \
        --bundle-identifier com.i7t5.edmund \
        --source-files Sources/edmd/App/Intents.swift \
        --swift-const-vals-list "$CONST_FILELIST" \
        --deployment-target 14.0 \
        --xcode-version "$(xcodebuild -version 2>/dev/null | tail -1 | awk '{print $NF}')" \
        >/dev/null 2>&1 \
        && echo "  → Contents/Resources/Metadata.appintents" \
        || echo "  ! metadata export failed; intents work but Shortcuts discovery unavailable" >&2
else
    echo "  ! no .swiftconstvalues from SwiftPM build; Shortcuts discovery unavailable" >&2
    echo "    (intents still compile; use the Services menu, or build via an Xcode project)" >&2
fi

# Embed Sparkle.framework so the installed bundle is self-contained.
# SwiftPM links Sparkle but doesn't copy the framework (which carries the XPC
# helpers and Autoupdate.app) into the bundle; without this the updater crashes
# on the first check because it can't locate its helper processes.
echo "Embedding Sparkle.framework..."
mkdir -p "${BUNDLE}/Contents/Frameworks"
SPARKLE_FW="$(find .build -type d -name 'Sparkle.framework' | grep -v '\.dSYM' | head -1)"
if [ -z "$SPARKLE_FW" ]; then
    echo "Error: Sparkle.framework not found in .build. Run 'swift build -c release' first." >&2
    exit 1
fi
cp -R "$SPARKLE_FW" "${BUNDLE}/Contents/Frameworks/"

# Fix the rpath so the binary resolves @rpath/Sparkle.framework at the bundle-
# relative path above rather than the build-artifacts path that won't exist once
# the app is installed.
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "${BUNDLE}/Contents/MacOS/${EXECUTABLE}" 2>/dev/null || true

# Assemble the Quick Look preview extension as an .appex in Contents/PlugIns.
# It's an executable target (SwiftPM has no app-extension product); its entry
# point is Foundation's NSExtensionMain via the linker flag in Package.swift.
# The link now includes the extension marker (Package.swift) so the appex is a
# real app extension to the rest of the system, not just a .appex-shaped folder.
# The appex gets its own copy of the shared rendering modules' resource bundles
# further down, *after* it is signed — see the resource-bundle loop below for
# why they have to sit at the product root in a flat shape.
echo "Assembling Quick Look extension..."
QL_NAME="EdmundQuickLook"
APPEX="${BUNDLE}/Contents/PlugIns/${QL_NAME}.appex"
mkdir -p "${APPEX}/Contents/MacOS" "${APPEX}/Contents/Resources"
cp ".build/release/${QL_NAME}" "${APPEX}/Contents/MacOS/${QL_NAME}"
cp Resources/QuickLookInfo.plist "${APPEX}/Contents/Info.plist"

# SwiftPM's resource bundles must keep the shape their *generated accessor*
# (`Bundle.module`) can read, and the shape is not cosmetic.
#
#   • A directory bundle that carries `Contents/` is a v2 bundle: Foundation
#     resolves its resources relative to `Contents/Resources`. `.copy(...)` lays
#     the payload out *flat* (at the bundle's own root), so a bundle given a
#     `Contents/Info.plist` but still holding a flat payload has no resource the
#     accessor can see — `url(forResource:withExtension:)` returns nil.
#   • With no `Contents/` at all, `resourceURL` *is* the bundle root and the
#     flat payload is found.
#
# SwiftMath's `MTFont.fontBundle` is
# `Bundle(url: Bundle.module.url(forResource: "mathFonts", withExtension: "bundle")!)!`
# — two force unwraps with no throwing path — so the first shape is a hard crash
# (EXC_BREAKPOINT / SIGTRAP on the main thread) the moment any `$…$` is rendered
# (issues #12/#13). Writing a `Contents/Info.plist` into *every* resource bundle
# is what produced it: the bundle looked legal to `codesign`, but its own
# accessor could no longer find the fonts. Every staged resource bundle is
# therefore kept flat.
#
# A flat bundle can still carry an identity, which is what issue #8 needed for
# the syntax definitions: a root `Info.plist` *is* read by Foundation on macOS
# (`Bundle(path:).bundleIdentifier` is non-nil when the root plist declares one).
# SwiftPM writes a root plist itself, but with only `CFBundleDevelopmentRegion`
# in it, which is why such a bundle reports a nil identifier — the layout was
# never the reason. `SyntaxDefinitionStore` only reaches for `Bundle.module`
# when the bundle is well-formed, and "well-formed" there is exactly
# `bundleIdentifier != nil`, so the syntax bundle gets a root plist with a real
# identifier and no `Contents/`.
echo "Staging SwiftPM resource bundles (flat, as their accessors expect)..."
for bundle in .build/release/*.bundle; do
    [ -e "$bundle" ] || continue
    echo "  · resource bundle: $(basename "$bundle")"
    # Repair a bundle staged by an earlier build of this script: a `Contents/`
    # holding only an `Info.plist` (no `Resources/`) under a flat payload is the
    # crashing shape, and it lives on in `.build` across builds, so the copy
    # below would ship it. A real v2 bundle (`Contents/Resources/…`) is left
    # alone — and the verification at the end of this script would catch it if
    # the accessor couldn't read it.
    if [ -d "$bundle/Contents" ] && [ ! -d "$bundle/Contents/Resources" ]; then
        echo "  → removing Contents/ from $(basename "$bundle") (flattening)"
        rm -rf "$bundle/Contents"
    fi
    case "$(basename "$bundle")" in
        SwiftMath_*)
            # No injected plist: SwiftMath never asks for an identifier, and
            # SwiftPM's own root plist is already there.
            ;;
        *)
            echo "  → writing root Info.plist for $(basename "$bundle")"
            RES_BUNDLE_ID="$(basename "$bundle" .bundle | tr '_' '.')"
            cat > "$bundle/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.i7t5.edmund.resources.${RES_BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${RES_BUNDLE_ID}</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)</string>
    <key>CFBundleVersion</key>
    <string>$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Info.plist)</string>
</dict>
</plist>
PLIST
            ;;
    esac
done

# Code sign the bundle as a properly *sealed* bundle — not just the binary.
#
# Why this matters: at install time Sparkle re-validates the downloaded update's
# Apple code signature (SUUpdateValidator). Even with a valid EdDSA signature, if
# the bundle reports as code-signed but fails SecStaticCodeCheckValidity, Sparkle
# rejects the update as "improperly signed and could not be validated." Signing
# only the standalone binary (as we used to) produces a bundle with no
# _CodeSignature seal, which fails that check — so every Sparkle update was
# rejected.
#
# Sign inside-out: Sparkle.framework first (its nested XPC helpers must be signed
# before macOS will launch them), then the whole .app. We seal the app while its
# root contains only Contents/, because codesign refuses to seal a bundle that
# has extra items at the .app root ("unsealed contents present in the bundle
# root" — reproducible in one command: codesign exits 1 for both a directory and
# a symlink placed there). The resource bundles have to live at the product root
# at runtime (see below), so they are copied in *after* sealing: the .app root
# for the app, and the .appex root for the extension, which is sealed before its
# bundles arrive for the same reason.
#
# So each product root ends up with unsealed items, which `codesign --verify`
# (and --strict) flag. Sparkle's actual check is non-strict
# (SecStaticCodeCheckValidityWithErrors with kSecCSCheckAllArchitectures), and it
# is the check that governs whether an update installs; the app-root trade-off
# has been shipped since the resource bundles were first embedded.
echo "Code signing..."
# Sign inside-out, then seal the app WITHOUT --deep. --deep on the outer .app
# would re-sign every nested item with default flags and reset the appex's
# identifier to the app's. Instead we sign each nested item explicitly (Sparkle
# deep so its own XPC helpers are covered; the appex on its own) and let the
# non-deep app sign just seal the container over the already-signed contents.
#
# The appex is signed WITHOUT entitlements, i.e. unsandboxed — on purpose.
# A Quick Look preview extension that renders in a WKWebView cannot be
# App-Sandboxed without also giving WebKit's own XPC services the entitlements
# they need; sandboxed with nothing else, WebKit's helper processes are refused,
# the load never completes, and Finder reports
# "扩展 com.i7t5.edmund.quicklook 在预览此文稿期间失败" with no other detail
# (issue #8). The host app is not sandboxed either, so the extension matches it:
# it reads only the file Quick Look hands it plus its own resources, has
# JavaScript disabled, and inlines every asset, so it never needs the network —
# which is enforced in code, not by a sandbox.
codesign --force --deep --sign - "${BUNDLE}/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --identifier "com.i7t5.edmund.quicklook" "$APPEX"
codesign --force --sign - --identifier "com.i7t5.edmd" "$BUNDLE"

# SwiftPM dependencies that ship resources (SwiftMath's math fonts) emit a
# per-target bundle next to the binary. The generated `Bundle.module` accessor
# looks for it at `Bundle.main.bundleURL` — the product root: the `.app` root
# for the app, the `.appex` root for the extension — and only otherwise at a
# hardcoded absolute `.build` path that doesn't exist once the app is installed.
# So the bundles must sit at both product roots, in their flat shape; copy them
# in *after* signing (they can't be sealed there — see above) so the bundles'
# own seals stay valid.
#
# Without the `.app` copy the app crashes the moment it renders any LaTeX. The
# appex needs the identical treatment: it links the same rendering pipeline
# (DocumentHTML → MathRendering → SwiftMath), so a Space-bar preview of a
# document with math reaches `MTFont.fontBundle` too, and `Bundle.main` there is
# the `.appex` — not the enclosing app.
echo "Copying SwiftPM resource bundles..."
for bundle in .build/release/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "${BUNDLE}/"
    cp -R "$bundle" "${APPEX}/"
done

# Fail the build — not the user's first `$E=mc^2$` — if the bundles above aren't
# where their accessors will look for them. The probe replays the accessor's own
# lookups (see the script for what each one is); it is cheap and has no state to
# get out of sync with the packaging, which is the point.
echo "Verifying resource-bundle layout..."
./scripts/verify-app-bundle.sh "$BUNDLE"

echo ""
echo "Done: ${BUNDLE}"
echo "To install: cp -R ${BUNDLE} /Applications/"
