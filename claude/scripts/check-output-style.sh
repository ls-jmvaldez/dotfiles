#!/usr/bin/env bash
# Assert that the outputStyle named in settings.json actually resolves.
#
# Plugin-supplied output styles register under "<pluginName>:<styleName>", and an
# unresolvable name yields null rather than an error, so the session silently
# falls back to the default. A wrong name therefore looks installed and does
# nothing. Neither the hook tests nor validate-plugins.sh can catch that, which
# is why this check exists as its own command.
#
# Usage: bash claude/scripts/check-output-style.sh
# Exit 0 when the name resolves or none is configured, 1 when it cannot resolve.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$SCRIPT_DIR/../settings.json"
MANIFEST="${CLAUDE_PLUGIN_MANIFEST:-$HOME/.claude/plugins/installed_plugins.json}"

if [ ! -f "$SETTINGS" ]; then
    printf 'FAIL: settings.json not found at %s\n' "$SETTINGS" >&2
    exit 1
fi

STYLE=$(jq -r '.outputStyle // empty' "$SETTINGS" 2>/dev/null)

if [ -z "$STYLE" ]; then
    echo "OK: no outputStyle configured, nothing to resolve"
    exit 0
fi

case "$STYLE" in
    *:*) ;;
    *)
        # Built-in styles ship with the binary and cannot be enumerated from
        # here. Flag it so a plugin style missing its namespace is visible,
        # since that is the exact mistake this check was written for.
        printf 'INFO: "%s" has no plugin namespace, assuming a built-in style.\n' "$STYLE"
        printf 'INFO: a plugin style must be written as "<plugin-name>:%s".\n' "$STYLE"
        exit 0
        ;;
esac

PLUGIN="${STYLE%%:*}"
NAME="${STYLE#*:}"

if [ ! -f "$MANIFEST" ]; then
    printf 'FAIL: %s references plugin "%s" but no plugin manifest exists at %s\n' \
        "$STYLE" "$PLUGIN" "$MANIFEST" >&2
    exit 1
fi

INSTALL_PATH=$(jq -r --arg p "$PLUGIN" \
    '.plugins | to_entries[] | select(.key | startswith($p + "@")) | .value[0].installPath // empty' \
    "$MANIFEST" 2>/dev/null | head -1)

if [ -z "$INSTALL_PATH" ]; then
    printf 'FAIL: plugin "%s" is not installed, so outputStyle "%s" resolves to null\n' \
        "$PLUGIN" "$STYLE" >&2
    printf '      The session would silently fall back to the default style.\n' >&2
    exit 1
fi

STYLE_FILE="$INSTALL_PATH/output-styles/$NAME.md"
if [ ! -f "$STYLE_FILE" ]; then
    printf 'FAIL: plugin "%s" is installed but has no output style "%s"\n' "$PLUGIN" "$NAME" >&2
    printf '      Expected: %s\n' "$STYLE_FILE" >&2
    exit 1
fi

printf 'OK: outputStyle "%s" resolves to %s\n' "$STYLE" "$STYLE_FILE"
