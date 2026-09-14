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
# Unlike the app's own SwiftMath bundle (copied to the .app root *after* the
# seal), the appex's resource bundles go inside Contents/Resources *before* it
# is signed, so they're sealed legally: an appex's Bundle.module resolves via
# Bundle.main.resourceURL, which for an .appex is Contents/Resources.
echo "Assembling Quick Look extension..."
QL_NAME="EdmundQuickLook"
APPEX="${BUNDLE}/Contents/PlugIns/${QL_NAME}.appex"
mkdir -p "${APPEX}/Contents/MacOS" "${APPEX}/Contents/Resources"
cp ".build/release/${QL_NAME}" "${APPEX}/Contents/MacOS/${QL_NAME}"
cp Resources/QuickLookInfo.plist "${APPEX}/Contents/Info.plist"

# The appex carries its own copy of the shared rendering modules' resource
# bundles (the syntax definitions). SwiftPM's `.copy("Resources/Syntaxes")`
# produces a bundle that is *only* a `Syntaxes/` folder — no
# `Contents/Info.plist` — and Foundation's generated `Bundle.module` accessor
# (SwiftPM ≥ 5.9 on macOS) fails its `bundleIdentifier != nil` precondition on
# such a bundle. That failure is a trap (EXC_BREAKPOINT / SIGTRAP, not a throw),
# so an appex shipped in that shape dies the first time a syntax definition is
# loaded. Make every resource bundle a legal bundle first, then stage it.
for bundle in .build/release/*.bundle; do
    [ -e "$bundle" ] || continue
    echo "  · resource bundle: $(basename "$bundle")"
    if [ ! -f "$bundle/Contents/Info.plist" ]; then
        echo "  → adding Info.plist to $(basename "$bundle")"
        RES_BUNDLE_ID="$(basename "$bundle" .bundle | tr '_' '.')"
        mkdir -p "$bundle/Contents"
        cat > "$bundle/Contents/Info.plist" <<PLIST
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
        # `.copy` lays the payload out flat (`<bundle>/Syntaxes`); a legal macOS
        # bundle keeps resources under `Contents/Resources`. Copy rather than
        # move: the syntax store probes both layouts, and the flat copy is the
        # one a generated `Bundle.module` accessor looks for.
        if [ -d "$bundle/Syntaxes" ] && [ ! -d "$bundle/Contents/Resources/Syntaxes" ]; then
            mkdir -p "$bundle/Contents/Resources"
            cp -R "$bundle/Syntaxes" "$bundle/Contents/Resources/Syntaxes"
        fi
    fi
    # Copy LAST: the appex must receive the bundle that now has its Info.plist
    # and its `Contents/Resources/Syntaxes` layout. Copying before that
    # transformation shipped the original, identifier-less directory — the shape
    # `Bundle.module` traps on.
    #
    # EXACTLY ONCE: BSD `cp -R` does not merge into an existing directory, it
    # copies the source *inside* it. A second copy of the same bundle — for
    # instance a separate loop that only wanted the SwiftMath one — therefore
    # reproduces the whole resource bundle one level deeper
    # (`…/SwiftMath_SwiftMath.bundle/mathFonts.bundle/KpMath-Light.plist`), and
    # `cp` then fails on every nested file as the target re-enters the source.
    # Everything the appex needs is already in this single pass.
    ditto "$bundle" "${APPEX}/Contents/Resources/$(basename "$bundle")"
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
# root"). The SwiftMath resource bundle has to live at the .app root at runtime
# (see below), so we copy it in *after* sealing. That leaves one unsealed item at
# the root, which `codesign --verify` (CLI) and --strict flag — but Sparkle's
# actual check is non-strict (SecStaticCodeCheckValidityWithErrors with
# kSecCSCheckAllArchitectures), which tolerates it. Verified end-to-end.
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
# per-target bundle next to the binary. The app resolves it explicitly —
# `MathFonts` probes Bundle.main's Resources *and* the executable's directory —
# because SwiftMath's own accessor (`Bundle.module`) traps the whole process
# when it can't find the bundle it was compiled against (issue #12). Shipping it
# in BOTH places means either probe succeeds: `Edmund.app/Contents/Resources`
# is what a normal install reads (and what the Quick Look appex reads, since its
# Bundle.main is its own .appex), and `.app/mathFonts.bundle` keeps the layout
# SwiftMath's generated accessor has always expected, for anything that reaches
# for it directly.
#
# Copies go in *after* sealing (they can't be sealed at the .app root — see
# above) for the SwiftMath target bundles, and BEFORE sealing inside
# Contents/Resources so the app's own signature covers them. Missing fonts are
# no longer fatal (the editor degrades to a readable Unicode approximation), so
# this step can no longer take the app down if it under-delivers — but it is
# still checked, because "fonts silently missing from every release" is exactly
# the class of bug that used to be invisible until a user opened an equation.
echo "Copying SwiftPM resource bundles..."
RESOURCE_BUNDLES=()
for bundle in .build/release/*.bundle; do
    [ -e "$bundle" ] || continue
    [ -f "$bundle/Contents/Info.plist" ] || continue
    RESOURCE_BUNDLES+=("$bundle")
    cp -R "$bundle" "${BUNDLE}/"
    cp -R "$bundle" "${BUNDLE}/Contents/Resources/"
done

# Which bundle carries the fonts, and whether it carries them *legally*.
#
# "The .otf is in there" and "SwiftMath can find it" are two different claims,
# and the gap between them is where this feature breaks: SwiftMath reads its
# fonts by asking a *Bundle* for a resource, so a font inside a directory that
# Foundation won't treat as a bundle is a font that doesn't exist — while still
# being a file that `find` and every existence check agree is present.
#
# So the failure is checked here, in the packaging step, with both halves:
# the SwiftMath bundle must be a legal `BNDL` (an `Info.plist` Foundation can
# read, with an identifier) *and* contain the font at the nested layout SwiftPM
# produces. When it doesn't, the app's explicit probe declines and equations
# render as readable Unicode rather than crashing — but a release that degrades
# maths silently is a bug in this script, so it says so loudly.
FONT_BUNDLE=""
for bundle in "${RESOURCE_BUNDLES[@]}"; do
    case "$(basename "$bundle")" in
        *SwiftMath*) FONT_BUNDLE="$bundle" ;;
    esac
done
if [ -z "$FONT_BUNDLE" ]; then
    echo "  ! no SwiftMath resource bundle in .build/release — math will render as plain Unicode" >&2
else
    # The directory must contain the OpenType font itself, not just be a
    # resource bundle with a plist: `MathFonts` reports unavailable when it
    # can't find `latinmodern-math.otf`, and SwiftMath traps if it gets that far.
    #
    # `.copy("mathFonts.bundle")` reproduces that directory verbatim, so the font
    # really lives at `SwiftMath_SwiftMath.bundle/mathFonts.bundle/…` — one level
    # deeper than the bundle name suggests. Checking only the bundle's own root
    # reported "no fonts" for a release that had every one of them, and the only
    # visible symptom was maths silently degrading to plain Unicode.
    FONT_FILE=""
    for candidate in "$FONT_BUNDLE/latinmodern-math.otf" \
                     "$FONT_BUNDLE/mathFonts.bundle/latinmodern-math.otf" \
                     "$FONT_BUNDLE/Contents/Resources/latinmodern-math.otf" \
                     "$FONT_BUNDLE/Contents/Resources/mathFonts.bundle/latinmodern-math.otf"; do
        if [ -f "$candidate" ]; then FONT_FILE="$candidate"; break; fi
    done
    if [ -n "$FONT_FILE" ]; then
        echo "  → math fonts packaged: $(basename "$FONT_BUNDLE") ($(basename "$(dirname "$FONT_FILE")")/latinmodern-math.otf)"
    else
        echo "  ! $(basename "$FONT_BUNDLE") has no latinmodern-math.otf — math will render as plain Unicode" >&2
    fi

    # The font is there; now check that Foundation would accept the container it
    # is in. This is the check `MathFonts` cannot make from the code side
    # (it runs on the user's machine, where the answer is already history) and
    # the reason 5.28.0 could ship a build whose fonts were all present and
    # unreachable at the same time.
    BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' \
        "$FONT_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
    FONT_DEST="${BUNDLE}/Contents/Resources/$(basename "$FONT_BUNDLE")"
    if [ -z "$BUNDLE_ID" ]; then
        echo "  ! $(basename "$FONT_BUNDLE")/Contents/Info.plist has no CFBundleIdentifier;" >&2
        echo "    Foundation will not treat it as a bundle, so SwiftMath cannot find" >&2
        echo "    the font it contains and maths degrades to plain Unicode." >&2
    else
        echo "  → fonts reachable as ${BUNDLE_ID}: $(basename "$(dirname "$FONT_FILE")")/latinmodern-math.otf"
    fi
    # Verify against the *copied* bundle too — the one the app will actually
    # resolve — not just the .build artifact it came from. A copy that dropped
    # the Info.plist, or landed at the wrong depth under Contents/Resources,
    # is exactly the shape that reads as "fonts shipped" and behaves as
    # "fonts missing".
    if [ ! -f "$FONT_DEST/latinmodern-math.otf" ] \
       && [ ! -f "$FONT_DEST/mathFonts.bundle/latinmodern-math.otf" ] \
       && [ ! -f "$FONT_DEST/Contents/Resources/mathFonts.bundle/latinmodern-math.otf" ]; then
        echo "  ! $(basename "$FONT_BUNDLE") reached the app bundle without its font" >&2
    fi
fi

echo ""
echo "Done: ${BUNDLE}"
echo "To install: cp -R ${BUNDLE} /Applications/"

# ── Mirror the SwiftPM resource bundles into the test bundle ─────────────────
#
# `swift test` builds `EdmundPackageTests.xctest`, whose Bundle.main is a
# temporary directory — neither `Contents/Resources` nor the executable's parent
# holds the per-target resource bundles, so `MathFonts` resolves nothing in the
# test process. That is the *correct* production behaviour (the editor degrades
# to readable Unicode rather than trapping, issue #12), but in the suite it makes
# every math assertion depend on which engine happened to win: the app would
# render an equation and the test would not. `Bundle.module` isn't an option —
# it traps on the identifier-less shape it can't find, which is the bug.
#
# So the test bundle gets exactly what the .app gets: the bundles beside the
# .xctest, and under `Contents/Resources` (an .xctest *is* a bundle, so that is
# its Bundle.main.resourceURL). This mirrors the app rather than papering over
# it — the tests then exercise the packaged layout, which is what ships.
TEST_BUNDLE="$(find .build -name '*.xctest' -maxdepth 4 2>/dev/null | head -1 || true)"
if [ -n "$TEST_BUNDLE" ] && [ -d "$TEST_BUNDLE" ]; then
    echo "Mirroring resource bundles into $(basename "$TEST_BUNDLE")..."
    mkdir -p "${TEST_BUNDLE}/Contents/Resources"
    for bundle in "${RESOURCE_BUNDLES[@]}"; do
        cp -R "$bundle" "${TEST_BUNDLE}/"
        cp -R "$bundle" "${TEST_BUNDLE}/Contents/Resources/"
    done
    for bundle in "${RESOURCE_BUNDLES[@]}"; do
        [ -f "${TEST_BUNDLE}/$(basename "$bundle")/Contents/Info.plist" ] \
            || [ -f "${TEST_BUNDLE}/Contents/Resources/$(basename "$bundle")/Contents/Info.plist" ] \
            || echo "  ! $(basename "$bundle") not reachable from the test bundle" >&2
    done
fi
