#!/usr/bin/env bash
set -euo pipefail

repo="${1:-subworkflows/interproscan6}"
patch="${2:-patches/interproscan6/0001-imported-workflow-localize-sequences-db.patch}"

if [[ ! -d "$repo/.git" && ! -f "$repo/.git" ]]; then
    echo "[error] InterProScan 6 submodule not found: $repo" >&2
    echo "        Run: git submodule update --init --recursive" >&2
    exit 1
fi

patch_abs="$(cd "$(dirname "$patch")" && pwd)/$(basename "$patch")"
commit="$(git -C "$repo" rev-parse --short HEAD)"
echo "[info] InterProScan 6 submodule: $repo@$commit"

if git -C "$repo" apply --reverse --check "$patch_abs" >/dev/null 2>&1; then
    echo "[info] patch already applied: $patch"
    exit 0
fi

git -C "$repo" apply --check "$patch_abs"
git -C "$repo" apply "$patch_abs"
echo "[info] applied patch: $patch"
