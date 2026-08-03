#!/bin/bash
# PreToolUse(Bash): keep visual verification off the user's foreground.
#
# Why this exists: capturing a screen *rect* grabs whatever window is in front,
# which on a machine the maintainer is actively using is their browser, not
# Edmund — and the usual "fix" (osascript frontmost + keystroke) types into
# whatever has focus. Both happened in one session; the correct tools already
# existed and were simply not reached for.
#
# Capture by CGWindow id instead (works on a background window, steals nothing),
# and drive the app in-process with -debug.reproScript rather than CGEvents.
#
# Reads the hook JSON on stdin, emits a deny decision or {}.

set -uo pipefail

cmd=$(jq -r '.tool_input.command // empty')
[[ -n "$cmd" ]] || { echo '{}'; exit 0; }

deny() {
  jq -nc --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# `screencapture -R x,y,w,h` / `-Rx,y,w,h` — a screen rect, not a window.
if grep -Eq '(^|[;&|[:space:]])screencapture([[:space:]]+-[^[:space:]]+)*[[:space:]]+-R' <<<"$cmd"; then
  deny 'screencapture -R captures a screen rect — it grabs whatever window is frontmost, which is the user'\''s app when they are at the machine (this has produced screenshots of the maintainer'\''s browser and terminal). Capture the Edmund window by CGWindow id instead, which works even when the window is behind and steals no focus:
  .claude/skills/edmund-live-repro-and-diagnostics/scripts/ui-harness.sh capture out.png
  (or capture-window.sh / winid.swift in the same directory; ARCHITECTURE §8 "Running & verifying the app").
Full-screen `screencapture out.png` with no -R is not blocked.'
fi

# System Events keystroke / key code / frontmost — types into whatever has focus.
if grep -q 'System Events' <<<"$cmd" &&
   grep -Eq 'keystroke|key code|set frontmost' <<<"$cmd"; then
  deny 'Synthesizing keystrokes through System Events types into whatever app currently has focus, and raising Edmund pulls the user out of what they were doing. Drive the running app in-process instead:
  edmd file.md -debug.reproScript script.txt   # caret / type / backspace / scroll / viewmode
See Sources/edmd/App/ReproScript.swift for the command list and the live-repro skill for the escalation ladder. If a real CGEvent path is genuinely required, ask the user first — they may be at the keyboard.'
fi

echo '{}'
