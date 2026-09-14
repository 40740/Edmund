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

        # Same trap, one directory deeper — and this is issue #14.
        #
        # Adding `Contents/Info.plist` above flips how Foundation classifies the
        # bundle, and that changes where `url(forResource:)` *looks*. CoreFoundation's
        # `_CFBundleGetBundleVersionForURL` picks the version by scanning for the
        # directory names present, and the order of its branches is load-bearing:
        # for a non-framework directory it checks `Contents` FIRST, then
        # `Resources`. A bundle that has both is therefore a version-2 "modern
        # Contents bundle", whose resource directory is `<bundle>/Contents/Resources`
        # — *not* the bundle root.
        #
        # So the moment this script added `Contents/Info.plist` to
        # `SwiftMath_SwiftMath.bundle` (to make it a legal bundle), that bundle
        # stopped being a flat bundle. Its payload lives at
        # `<bundle>/mathFonts.bundle/…`, but `url(forResource:"mathFonts",
        # withExtension:"bundle")` now searched `<bundle>/Contents/Resources`,
        # found nothing, returned nil — and SwiftMath's `MTFont.fontBundle`
        # force-unwraps that. nil + `!` is SIGTRAP (EXC_BREAKPOINT), which is
        # exactly the crash in issue #14. Adding a legal `Info.plist` to fix one
        # trap is what created the other.
        #
        # The fix is not to remove the Info.plist — a legal bundle is what
        # `Bundle(path:)` and code signing both want — but to put the payload
        # where the resource directory now points. Move each payload
        # subdirectory under `Contents/Resources`, which is the single place a
        # version-2 Contents bundle searches.
        #
        # MOVE, not copy. The flat root copy is read by nothing once the bundle
        # has a `Contents/` directory: both readers go through
        # `url(forResource:)`, which resolves to `Contents/Resources` for a
        # version-2 bundle. `swift run` and `swift test` read the untouched
        # `.build/<config>` bundle, not this one, so they lose nothing either.
        # Keeping both copies just doubles ~4 MB of fonts in the DMG — one copy
        # is already staged again for the appex.
        #
        # This is the ONE change from v5.29.0's approach that is kept as-is: the
        # payload move is what makes the lookup resolve. What was wrong there was
        # *when* it happened, not that it happened (see below).
        if [ -d "$bundle/Contents" ]; then
            mkdir -p "$bundle/Contents/Resources"
            for payload in "$bundle"/*/; do
                name="$(basename "$payload")"
                [ "$name" = "Contents" ] && continue
                [ -d "$bundle/Contents/Resources/$name" ] && continue
                mv "$payload" "$bundle/Contents/Resources/$name"
            done
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

echo "Copying SwiftPM resource bundles into Contents/Resources..."
RESOURCE_BUNDLES=()
for bundle in .build/release/*.bundle; do
    [ -e "$bundle" ] || continue
    [ -f "$bundle/Contents/Info.plist" ] || continue
    RESOURCE_BUNDLES+=("$bundle")
    # `Contents/Resources` is `Bundle.main.resourceURL`, and it is the only root
    # inside the sealed bundle where a nested resource bundle can live: `codesign`
    # refuses to seal a loose item at the `.app` root, so a copy placed there
    # makes the whole app fail `codesign --verify` — which Gatekeeper reports to
    # the user as "Edmund.app is damaged and can't be opened" (issue #14).
    #
    # Staging BOTH bundles here (not only the syntax one) is deliberate. Each
    # resource bundle is given a `Contents/Info.plist` above, which makes it a
    # version-2 Contents bundle, so `url(forResource:)` searches its own
    # `Contents/Resources` — and that is where the mirrored payload is. Asking
    # for the bundle from `Bundle.main.resourceURL` therefore resolves, for
    # SwiftMath just as much as for the syntax definitions.
    cp -R "$bundle" "${BUNDLE}/Contents/Resources/"
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
# before macOS will launch them), then the whole .app.
#
# ORDER IS LOAD-BEARING: every resource is staged *before* this step, and nothing
# is written into the bundle afterwards. `_CodeSignature/CodeResources` is a
# snapshot of the bundle taken when `codesign` runs, so a later write leaves it
# describing bytes that are not where it says — and Gatekeeper refuses to launch
# a bundle whose seal does not match, before any of the app's code runs. The user
# sees "Edmund.app is damaged and can't be opened" and there is no crash report,
# because there is no crash (v5.29.0, issue #14). That is not a "broken
# download": `codesign --verify` is the check, and `release.yml` runs it against
# the mounted DMG.
#
# Nothing may sit at the `.app` root either — `codesign` rejects loose items
# there ("unsealed contents present in the bundle root") on both the strict and
# the non-strict check. Resource bundles live under `Contents/Resources`, where
# they are sealed normally and where `Bundle.main.resourceURL` finds them.
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
# Missing fonts are no longer fatal (the editor degrades to a readable Unicode
# approximation), so this step cannot take the app down if it under-delivers —
# but it is still checked, because "fonts silently missing from every release"
# is exactly the class of bug that used to be invisible until a user opened an
# equation, and because the *location* is what decides whether SwiftMath's own
# lookup resolves or traps.
FONT_BUNDLE=""
for bundle in "${RESOURCE_BUNDLES[@]}"; do
    case "$(basename "$bundle")" in
        *SwiftMath*) FONT_BUNDLE="$bundle" ;;
    esac
done
if [ -z "$FONT_BUNDLE" ]; then
    echo "  ! no SwiftMath resource bundle in .build/release — math will render as plain Unicode" >&2
else
    # Verify the layout SwiftMath's *own* lookup will use, not merely that a font
    # exists somewhere in the tree. That distinction is the whole of issue #14:
    # a release can ship every font on disk and still trap, because they sit in a
    # directory the lookup does not read.
    #
    # Two readers, two locations, and both are asserted:
    #
    #   1. SwiftMath's generated `Bundle.module` resolves
    #      `Bundle.main.bundleURL/SwiftMath_SwiftMath.bundle` — the **app root**.
    #      That path now holds nothing (a loose item there fails
    #      `codesign --verify`), so what must make SwiftMath resolve is the
    #      bundle the app *does* open: `MathFonts` passes its own directory to
    #      SwiftMath, and `Contents/Resources/SwiftMath_SwiftMath.bundle` is
    #      reachable from `Bundle.main.resourceURL`.
    #   2. `MathFonts` itself, which is what decides `isAvailable` and therefore
    #      whether `SwiftMathRenderer` calls into SwiftMath at all.
    #
    # The bundle is a version-2 Contents bundle (the script writes its
    # `Contents/Info.plist`), so `url(forResource:)` searches its own
    # `Contents/Resources` — so the payload must be mirrored there, which the
    # loop above does. Assert that exact path; it is the one that resolves.
    FONT_BUNDLE_NAME="$(basename "$FONT_BUNDLE")"
    FONT_PAYLOAD="mathFonts.bundle/latinmodern-math.otf"

    FONT_FILE=""
    for candidate in "$FONT_BUNDLE/Contents/Resources/$FONT_PAYLOAD" \
                     "$FONT_BUNDLE/Contents/Resources/latinmodern-math.otf"; do
        if [ -f "$candidate" ]; then FONT_FILE="$candidate"; break; fi
    done

    # The shipped locations a reader uses. Each is asserted separately, because
    # "present but in a layout nothing reads" is exactly what shipped in v5.28.1
    # and again in v5.29.0 — with a crash, or with maths silently degrading.
    missing=0
    for location in \
        "${BUNDLE}/Contents/Resources/${FONT_BUNDLE_NAME}/Contents/Resources/$FONT_PAYLOAD" \
        "${APPEX}/Contents/Resources/${FONT_BUNDLE_NAME}/Contents/Resources/$FONT_PAYLOAD"; do
        if [ ! -f "$location" ]; then
            echo "  ! math payload missing from a location a lookup reads:" >&2
            echo "    ${location}" >&2
            missing=1
        fi
    done
    # And nothing at the app root: a loose item there fails `codesign --verify`,
    # which Gatekeeper reports as "Edmund.app is damaged" (issue #14).
    if [ -e "${BUNDLE}/${FONT_BUNDLE_NAME}" ]; then
        echo "  ! ${FONT_BUNDLE_NAME} was staged at the .app root, where codesign" >&2
        echo "    cannot seal it — Gatekeeper would refuse to launch the app." >&2
        missing=1
    fi

    if [ -n "$FONT_FILE" ] && [ "$missing" -eq 0 ]; then
        echo "  → math fonts packaged: ${FONT_BUNDLE_NAME} ($(basename "$(dirname "$FONT_FILE")")/latinmodern-math.otf)"
        echo "    verified in .app Contents/Resources and appex Contents/Resources"
    else
        echo "    A missing copy means a lookup reaches nil and MTFont.fontBundle" >&2
        echo "    force-unwraps it (SIGTRAP, issue #14). Maths will render as plain" >&2
        echo "    Unicode, or the app will crash, depending on which." >&2
    fi
fi

echo ""
echo "Done: ${BUNDLE}"
echo "To install: cp -R ${BUNDLE} /Applications/"

# ── Mirror the SwiftPM resource bundles into the test bundle ─────────────────
#
# The suite runs out of Xcode's `swift-pm` runner, so `Bundle.main` in the test
# process is that toolchain binary — neither `Contents/Resources` nor the
# executable's parent holds the per-target resource bundles, and staging them
# into the `.xctest` cannot be seen through `Bundle.main` at all. CI therefore
# points `MathFonts` at the copy staged here with `EDMUND_MATH_FONTS_BUNDLE`
# (see the `Test` step), which is validated exactly like any other candidate.
#
# Without this, `MathFonts` is unavailable in the suite, so every math
# assertion depends on which engine happened to win: the app renders an
# equation and the test does not. `Bundle.module` isn't an option — it traps on
# the identifier-less shape it can't find, which is the bug.
#
# So the test bundle gets exactly what the .app gets: the bundles beside the
# .xctest, and under `Contents/Resources` (an .xctest *is* a bundle, so that is
# its own resource directory). This mirrors the app rather than papering over
# it — the tests then exercise the packaged layout, which is what ships.
# Pinned to debug: that is `swift test`'s configuration, so it is the .xctest
# the suite actually runs — and the one CI points EDMUND_MATH_FONTS_BUNDLE at.
# Both releases and debug build dirs can exist here (this script builds
# release), and mirroring into the wrong one stages nothing the suite can see.
TEST_BUNDLE="$(find .build -name '*.xctest' -path '*debug*' -maxdepth 4 2>/dev/null | head -1 || true)"
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
