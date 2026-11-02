#!/usr/bin/env bash
# Moves to a newer NewPipeExtractor. Usage: update-extractor.sh [commit-or-tag] (default: dev tip)
#
# 1. fetches upstream and pins the requested commit in extractor/upstream.lock
# 2. re-applies extractor/patches/; a conflict stops here with conflict markers in the checkout
# 3. rebuilds the bundle and runs the live test suite under Bun, if Bun is installed
#
# After resolving a conflict in vendor/NewPipeExtractor, run: scripts/refresh-patch.sh
# then run this script's remaining step: scripts/build-extractor.sh
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/vendor/NewPipeExtractor"
target="${1:-origin/dev}"

[ -d "$src/.git" ] || git clone --quiet https://github.com/TeamNewPipe/NewPipeExtractor.git "$src"
git -C "$src" fetch --quiet --tags origin
commit="$(git -C "$src" rev-parse "$target^{commit}")"
previous="$(tr -d '[:space:]' < "$root/extractor/upstream.lock")"
echo "Updating NewPipeExtractor: ${previous:0:9} -> ${commit:0:9}"
echo "$commit" > "$root/extractor/upstream.lock"

# Library versions the bundle must match. They live in upstream's catalog, not here.
echo "Upstream dependency changes (compare with extractor/build.gradle.kts):"
git -C "$src" diff "$previous" "$commit" -- gradle/libs.versions.toml | grep -E '^[-+](jsoup|teamnewpipe-nanojson|jsr305)' || echo "  none"

"$root/scripts/build-extractor.sh"

if command -v bun >/dev/null; then
    (cd "$root/extractor" && BUN_JSC_useJIT=0 bun test/harness.mjs "$root/ios/SourPipe/Resources/extractor.jsbundle")
else
    echo "Bun not found: skipped the test suite (extractor/test/harness.mjs)."
fi
