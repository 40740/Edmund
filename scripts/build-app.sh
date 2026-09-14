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

# The appex carries its own copies of the shared rendering module resource
# bundles (the syntax definitions) and of SwiftMath's math fonts. SwiftPM's
# `.copy("Resources/Syntaxes")` produces a bundle that is *only* a `Syntaxes/`
# folder — **no `Info.plist` at all** — and Foundation's generated
# `Bundle.module` accessor (SwiftPM ≥ 5.9 on macOS) fails its
# `bundleIdentifier != nil` precondition on such a bundle. That failure is a
# trap (EXC_BREAKPOINT / SIGTRAP, not a throw), so an appex shipped in that
# shape dies the first time a syntax definition is loaded (issue #8).
#
# Every resource bundle gets an identifier below, and it is a **root**
# `Info.plist` rather than one under `Contents/`: a `Contents/` directory would
# make Foundation classify the bundle as version-2 and search
# `Contents/Resources`, moving the resource directory away from where `.copy`
# put the payload — which is issue #14. Flat identifier, flat payload, one
# consistent answer for every reader.
for bundle in .build/release/*.bundle; do
    [ -e "$bundle" ] || continue
    echo "  · resource bundle: $(basename "$bundle")"

    # Give each resource bundle a *flat* identifier.
    #
    # SwiftPM's generated `Bundle.module` accessor asserts
    # `bundleIdentifier != nil`, and a `.copy`-only bundle (just `Syntaxes/` or
    # `mathFonts.bundle/`) has no `Info.plist` at all, so it fails that
    # precondition — a trap, not a throw (issue #8). A flat `Info.plist` at the
    # bundle root fixes that **without** introducing a `Contents/` directory,
    # and that distinction turns out to be the whole ball game:
    #
    #   * With no `Contents/`, Foundation treats the directory as a *flat
    #     bundle*: `url(forResource:)` searches the bundle root, which is exactly
    #     where `.copy` put the payload. SwiftMath's lookup succeeds.
    #   * With a `Contents/` directory present, CoreFoundation's
    #     `_CFBundleGetBundleVersionForURL` classifies it as a version-2 Contents
    #     bundle (its non-framework branch tests `Contents` **before**
    #     `Resources`, deliberately), so the resource directory moves to
    #     `Contents/Resources` and a root-level payload becomes invisible —
    #     `url(forResource:)` returns nil and `MTFont.fontBundle` force-unwraps
    #     it (issue #14).
    #
    # v5.28.1 wrote `Contents/Info.plist`, which got the identifier *and* flipped
    # the classification; the shipped fix then had to move the payload into
    # `Contents/Resources` to match, and that is the change that produced both
    # the crash regression and the "damaged" bundle. A root `Info.plist` sidesteps
    # the whole conflict: the bundle stays flat, so payload location and
    # classification agree by construction.
    #
    # `codesign` is fine with the flat shape too — it is what SwiftPM produces,
    # and the root holds only `Info.plist` plus the payload directory, both of
    # which its rules accept. (A `Contents/` *and* a loose root payload is what
    # it rejects as "unsealed contents present in the bundle root".)
    if [ ! -f "$bundle/Info.plist" ]; then
        echo "  → adding flat Info.plist to $(basename "$bundle")"
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
        # A stray `Contents/` left by an earlier step would re-flip the
        # classification and hide the payload. Fail loudly rather than ship a
        # bundle whose two readers disagree — that is issue #14's shape.
        if [ -d "$bundle/Contents" ]; then
            echo "  ! $(basename "$bundle") has a Contents/ directory, which makes" >&2
            echo "    Foundation search Contents/Resources while the payload sits at the" >&2
            echo "    root — url(forResource:) then returns nil and SwiftMath traps." >&2
            exit 1
        fi
    fi

    # Copy LAST: the appex must receive the bundle that now has its Info.plist.
    # Copying before that transformation ships the original, identifier-less
    # directory — the shape `Bundle.module` traps on.
    #
    # EXACTLY ONCE: BSD `cp -R` does not merge into an existing directory, it
    # copies the source *inside* it. A second copy of the same bundle — for
    # instance a separate loop that only wanted the SwiftMath one — therefore
    # reproduces the whole resource bundle one level deeper
    # (`…/SwiftMath_SwiftMath.bundle/mathFonts.bundle/KpMath-Light.plist`), and
    # `cp` then fails on every nested file as the target re-enters the source.
    # Everything the appex needs is already in this single pass.
    # `Contents/Resources` is exactly where the appex's generated accessor
    # resolves its resources from (`Bundle.main` in an `.appex` answers
    # `resourceURL` with that directory), and it is the shape v5.28.1 shipped.
    # Nothing goes at the appex *root*: an `.appex` root may hold only
    # `Contents/`, so a loose resource-bundle directory there is the
    # "unsealed contents present in the bundle root" that `codesign` refuses —
    # and the accessor never looks there anyway.
    ditto "$bundle" "${APPEX}/Contents/Resources/$(basename "$bundle")"
done

# Resource bundles the app itself must find, staged at both roots its own
# readers use, and — critically — staged **before** the app is sealed, so
# `_CodeSignature/CodeResources` describes exactly what ships.
#
#   * The `.app` root is `Bundle.main.bundleURL`, the only root SwiftMath's
#     accessor searches on a shipped app. Its fallback is an absolute
#     `.build/...` path fixed at *SwiftMath's* compile time — the CI machine's,
#     never present on a user's Mac — and failure is `fatalError`, wrapped in
#     another `!` by `MTFont.fontBundle`. A missing copy here is the crash in
#     issue #14; that is exactly what v5.29.0 shipped.
#   * `Contents/Resources` is `Bundle.main.resourceURL`, which this repo's
#     `MathFonts` probes. Both locations get a bundle so the two readers cannot
#     disagree about whether the fonts are available — the disagreement *is* the
#     bug class, not any single layout.
echo "Copying SwiftPM resource bundles into Contents/Resources..."
RESOURCE_BUNDLES=()
for bundle in .build/release/*.bundle; do
    [ -e "$bundle" ] || continue
    [ -f "$bundle/Info.plist" ] || continue
    RESOURCE_BUNDLES+=("$bundle")
    # Inside the sealed subtree, so this must happen *before* the app is signed.
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
# ORDER IS LOAD-BEARING: every resource this app ships is staged *before* this
# step, including the SwiftMath bundle at the .app root. Writing a file into an
# already-sealed bundle leaves `_CodeSignature/CodeResources` describing bytes
# that are no longer where it says they are, and Gatekeeper refuses to launch a
# bundle whose seal does not match — the user sees "Edmund.app is damaged and
# can't be opened", with no crash report because the app never starts (issue
# #14). That is not a "broken download"; `codesign --verify --strict` is the
# check, and `release.yml` now runs it against the shipped DMG.
#
# `codesign` refuses to seal a bundle with extra items at the .app root
# ("unsealed contents present in the bundle root"), but a *resource bundle* at
# the root is sealable — it is a nested bundle, described in `CodeResources`
# like any other. So the SwiftMath bundle can live at the .app root (where
# SwiftMath's `Bundle.module` looks) and still be covered by the seal.
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
# Nested resource bundles are signed before their container, so the container's
# `CodeResources` describes a signed nested bundle rather than a raw directory.
# These bundles are *flat* (a root `Info.plist` plus their payload directory, no
# `Contents/`), which is the shape SwiftPM itself produces and the shape
# `codesign` accepts — unlike a bundle that carries `Contents/` *and* a loose
# root payload, which it rejects as "unsealed contents present in the bundle
# root". Signing is best-effort here on purpose: `codesign` versions differ on
# what they will seal, and a failure to seal a nested bundle must not turn into
# a confusing build error when the container seal is what actually matters.
for bundle in .build/release/*.bundle; do
    name="$(basename "$bundle")"
    location="${APPEX}/Contents/Resources/${name}"
    [ -e "$location" ] && codesign --force --sign - "$location" || true
done
codesign --force --sign - --identifier "com.i7t5.edmund.quicklook" "$APPEX"
codesign --force --sign - --identifier "com.i7t5.edmd" "$BUNDLE"

# The app-root copy, AFTER the app is sealed — and that ordering is deliberate.
#
# SwiftPM's generated accessor resolves the bundle as
# `Bundle.main.bundleURL.appendingPathComponent("SwiftMath_SwiftMath.bundle")`,
# i.e. **`Edmund.app/SwiftMath_SwiftMath.bundle`**. Nothing under `Contents/`
# satisfies it, and its only fallback is an absolute `.build/...` path baked in
# on the CI machine — so a missing root copy is the `fatalError` that
# `MTFont.fontBundle` turns into SIGTRAP. This copy is the difference between
# "equations render" and "the app dies on the first `$…$` document" (issue #14).
#
# It has to come after `codesign`, because `codesign` refuses to seal a bundle
# with a loose item at the `.app` root ("unsealed contents present in the bundle
# root"). The trade is deliberate and matches what shipped and worked before
# (v5.28.1): the root item is not described by the seal, so a *strict* verify
# reports it, but the non-strict validity check Gatekeeper uses to launch the app
# tolerates items outside the sealed `Contents/` subtree.
#
# The failure mode this is NOT allowed to become: writing inside the sealed tree
# after signing. That leaves the seal describing bytes that are not where it
# says, and Gatekeeper refuses to launch the app — "Edmund.app is damaged and
# can't be opened", with no crash report (v5.29.0, issue #14). Only the `.app`
# root is touched here; `Contents/**` was finalised before the seal.
for bundle in "${RESOURCE_BUNDLES[@]}"; do
    name="$(basename "$bundle")"
    rm -rf "${BUNDLE:?}/${name}"
    cp -R "$bundle" "${BUNDLE}/"
done

FONT_BUNDLE=""
for bundle in "${RESOURCE_BUNDLES[@]}"; do
    case "$(basename "$bundle")" in
        *SwiftMath*) FONT_BUNDLE="$bundle" ;;
    esac
done
if [ -z "$FONT_BUNDLE" ]; then
    echo "  ! no SwiftMath resource bundle in .build/release — math will render as plain Unicode" >&2
else
    # Verify every location a lookup actually reads, not merely that a font
    # exists somewhere in the tree. That distinction is the whole of issue #14:
    # v5.29.0 shipped every font on disk and still trapped, because the payload
    # was in a location the lookup that force-unwraps the nil never reads.
    #
    # Three readers matter, and each gets its own assertion:
    #
    #   1. `Bundle.main.bundleURL` — SwiftMath's generated `Bundle.module` on the
    #      .app. It looks at the **app root**, and a missing bundle there is the
    #      `fatalError` that `MTFont.fontBundle` turns into SIGTRAP (issue #14).
    #   2. `Bundle.main.resourceURL` then `bundleURL` — this repo's `MathFonts`.
    #      Its first hit decides, so it must agree with (1).
    #   3. The appex's root — SwiftMath's `Bundle.module` when `Bundle.main` is
    #      the `.appex`. Missing here degrades Quick Look equations silently.
    FONT_BUNDLE_NAME="$(basename "$FONT_BUNDLE")"
    FONT_PAYLOAD="mathFonts.bundle/latinmodern-math.otf"

    FONT_FILE=""
    for candidate in "$FONT_BUNDLE/$FONT_PAYLOAD" \
                     "$FONT_BUNDLE/Contents/Resources/$FONT_PAYLOAD" \
                     "$FONT_BUNDLE/latinmodern-math.otf"; do
        if [ -f "$candidate" ]; then FONT_FILE="$candidate"; break; fi
    done

    # A `Contents/` directory next to a root-level payload is the exact
    # configuration that makes Foundation search `Contents/Resources` while the
    # fonts sit at the root — `url(forResource:)` returns nil and
    # `MTFont.fontBundle` force-unwraps it (issue #14). Assert the bundle is
    # flat so this can never ship again.
    if [ -d "$FONT_BUNDLE/Contents" ]; then
        echo "  ! ${FONT_BUNDLE_NAME} carries a Contents/ directory, which makes" >&2
        echo "    Foundation look in Contents/Resources while the payload is at the" >&2
        echo "    root. Maths would crash (issue #14)." >&2
        exit 1
    fi

    # The three shipped locations. Each is asserted separately because each one
    # is a different reader's only chance — and "present but in the layout
    # nothing reads" is exactly the failure this whole check exists to catch.
    missing=0
    for location in \
        "${BUNDLE}/${FONT_BUNDLE_NAME}/mathFonts.bundle/latinmodern-math.otf" \
        "${BUNDLE}/Contents/Resources/${FONT_BUNDLE_NAME}/mathFonts.bundle/latinmodern-math.otf" \
        "${APPEX}/Contents/Resources/${FONT_BUNDLE_NAME}/mathFonts.bundle/latinmodern-math.otf"; do
        if [ ! -f "$location" ]; then
            echo "  ! math payload missing at a location a lookup reads:" >&2
            echo "    ${location}" >&2
            missing=1
        fi
    done

    if [ -n "$FONT_FILE" ] && [ "$missing" -eq 0 ]; then
        echo "  → math fonts packaged: ${FONT_BUNDLE_NAME} ($(basename "$(dirname "$FONT_FILE")")/latinmodern-math.otf)"
        echo "    verified at: .app root, .app Contents/Resources, appex Contents/Resources"
    else
        echo "    A missing copy means one of SwiftMath's lookups reaches nil and" >&2
        echo "    MTFont.fontBundle force-unwraps it (SIGTRAP, issue #14). Maths will" >&2
        echo "    render as plain Unicode, or the app will crash, depending on which." >&2
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
        # The bundles are flat, so the identifier is a root `Info.plist`. Check
        # the same flat shape the app ships, at both roots the suite reads.
        [ -f "${TEST_BUNDLE}/$(basename "$bundle")/Info.plist" ] \
            || [ -f "${TEST_BUNDLE}/Contents/Resources/$(basename "$bundle")/Info.plist" ] \
            || echo "  ! $(basename "$bundle") not reachable from the test bundle" >&2
    done
fi
