#!/usr/bin/env bash
# Sync Ghostty/ with an upstream Ghostty commit as ONE linear commit.
#
# Usage: GhostCode/scripts/sync-upstream.sh <upstream-commit> [--base <commit>]
#
# The current upstream base is read from the newest "Ghostty-Upstream:" trailer
# in HEAD's history (override with --base). The upstream changes base..new are
# replayed under Ghostty/ with a 3-way cherry-pick, so only files GhostCode
# patched can conflict. On conflicts: resolve, `git add`, then
# `git cherry-pick --continue`. The new commit records the next base.
set -euo pipefail

prefix=Ghostty
trailer=Ghostty-Upstream

usage() { echo "usage: $0 <upstream-commit> [--base <commit>]" >&2; exit 2; }

new=""
base=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --base) [[ $# -ge 2 ]] || usage; base="$2"; shift 2 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        -*) usage ;;
        *) [[ -z "$new" ]] || usage; new="$1"; shift ;;
    esac
done
[[ -n "$new" ]] || usage

cd "$(git rev-parse --show-toplevel)"

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "error: working tree has uncommitted changes" >&2
    exit 1
fi

if [[ -z "$base" ]]; then
    base=$(git log -1 --grep="^$trailer: " --format="%(trailers:key=$trailer,valueonly)" HEAD | tr -d '[:space:]')
    if [[ -z "$base" ]]; then
        echo "error: no '$trailer:' trailer found in history; pass --base <commit>" >&2
        exit 1
    fi
fi

base=$(git rev-parse --verify "$base^{commit}")
new=$(git rev-parse --verify "$new^{commit}")

if [[ "$base" == "$new" ]]; then
    echo "$prefix/ is already at ${new:0:9}"
    exit 0
fi

if ! git merge-base --is-ancestor "$base" "$new"; then
    echo "error: ${new:0:9} does not descend from base ${base:0:9}" >&2
    exit 1
fi

# Build a tree that holds an upstream commit's tree under $prefix/.
wrap_tree() {
    printf '040000 tree %s\t%s\n' "$(git rev-parse "$1^{tree}")" "$prefix" | git mktree
}

count=$(git rev-list --count "$base..$new")
short_base=$(git rev-parse --short "$base")
short_new=$(git rev-parse --short "$new")

msg="Sync upstream Ghostty to $short_new

- Apply $count upstream commits from $short_base to $short_new under $prefix/

$trailer: $new"

# A synthetic two-commit chain (base -> new), both wrapped under $prefix/.
# Cherry-picking its tip applies exactly the upstream diff onto HEAD.
base_commit=$(git commit-tree "$(wrap_tree "$base")" -m "upstream $short_base")
sync_commit=$(git commit-tree "$(wrap_tree "$new")" -p "$base_commit" -m "$msg")

echo "Syncing $prefix/ from $short_base to $short_new ($count upstream commits)"
git cherry-pick --allow-empty "$sync_commit"
