#!/usr/bin/env bash
# sync-profile.sh - Regenerates unix/profile/ from the pwsh-flavored ../profile/.
#
# The Windows tree (../profile) references .ps1 scripts run with pwsh and
# CamelCase flags. The unix tree needs the same docs pointing at .sh scripts
# run with bash and kebab-case flags. This script:
#   1. Copies ../profile -> ./profile (replacing it)
#   2. Rewrites script references and flags
#   3. Adds ".sh": "bash" to the prepmerge language map
#
# Run it after editing anything in ../profile, then review:
#   git diff unix/profile
#
# Usage (from anywhere):
#   bash unix/sync-profile.sh

set -eu

UNIX_DIR=$(cd "$(dirname "$0")" && pwd)
SRC_DIR="$UNIX_DIR/../profile"
DEST_DIR="$UNIX_DIR/profile"

if [ ! -d "$SRC_DIR" ]; then
    printf 'Error: source profile not found: %s\n' "$SRC_DIR" >&2
    exit 1
fi

printf 'Syncing %s -> %s\n' "$SRC_DIR" "$DEST_DIR"

rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"
cp -R "$SRC_DIR/." "$DEST_DIR/"

# Strip install artifacts that should never ship
rm -rf "$DEST_DIR/.ocx" "$DEST_DIR/node_modules" "$DEST_DIR/bun.lock" "$DEST_DIR/package-lock.json" 2>/dev/null || true
rm -f "$DEST_DIR/.DS_Store" 2>/dev/null || true

transform_file() {
    f="$1"
    tmp="$f.sync-tmp"
    if sed -E \
        -e 's|pwsh[[:space:]]+(\./scripts/[a-z0-9-]+)\.ps1|bash \1.sh|g' \
        -e 's|pwsh[[:space:]]+(\./scripts/[a-z0-9-]+)\*|bash \1*|g' \
        -e 's|([a-z0-9-]+)\.ps1|\1.sh|g' \
        -e 's|--DryRun|--dry-run|g' \
        -e 's|--Strategy|--strategy|g' \
        -e 's|--Message|--message|g' \
        -e 's|-DryRun|--dry-run|g' \
        -e 's|-Strategy|--strategy|g' \
        -e 's|-Message|--message|g' \
        -e 's|-MergeTarget|--merge-target|g' \
        -e 's|-Background|--background|g' \
        -e $'s/\r$//' \
        "$f" > "$tmp"; then
        mv "$tmp" "$f"
    else
        rm -f "$tmp"
        printf 'Error: transform failed: %s\n' "$f" >&2
        exit 1
    fi
}

file_count=0
while IFS= read -r f; do
    transform_file "$f"
    file_count=$((file_count + 1))
done < <(find "$DEST_DIR" -type f)

# File-specific: prepmerge language map gains ".sh": "bash"
prepmerge="$DEST_DIR/plugins/prepmerge_tui.tsx"
if [ -f "$prepmerge" ]; then
    tmp="$prepmerge.sync-tmp"
    if sed -E 's|"\.ps1": "powershell",|".ps1": "powershell", ".sh": "bash",|' "$prepmerge" > "$tmp"; then
        mv "$tmp" "$prepmerge"
    else
        rm -f "$tmp"
        printf 'Error: prepmerge language map update failed\n' >&2
        exit 1
    fi
fi

printf 'Done: %s files copied + transformed.\n' "$file_count"
printf 'Review changes: git diff unix/profile\n'
