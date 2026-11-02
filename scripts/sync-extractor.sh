#!/usr/bin/env bash
# Puts vendor/NewPipeExtractor at the commit in extractor/upstream.lock with extractor/patches/
# applied. Discards local edits in that checkout: keep changes as patches (see README).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/vendor/NewPipeExtractor"
url="https://github.com/TeamNewPipe/NewPipeExtractor.git"
commit="$(tr -d '[:space:]' < "$root/extractor/upstream.lock")"

if [ ! -d "$src/.git" ]; then
    mkdir -p "$root/vendor"
    git clone --quiet "$url" "$src"
fi
if ! git -C "$src" cat-file -e "$commit^{commit}" 2>/dev/null; then
    git -C "$src" fetch --quiet origin
fi
git -C "$src" checkout --quiet --force --detach "$commit"
git -C "$src" clean -fdq

shopt -s nullglob
for patch in "$root"/extractor/patches/*.patch; do
    echo "Applying $(basename "$patch")"
    git -C "$src" apply --3way --whitespace=nowarn "$patch"
done
git -C "$src" reset --quiet   # leave patch results unstaged so `git diff` shows them
echo "NewPipeExtractor is at $(git -C "$src" rev-parse --short HEAD) with patches applied."
