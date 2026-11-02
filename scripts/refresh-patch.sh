#!/usr/bin/env bash
# Records the current edits in vendor/NewPipeExtractor as the single SourPipe patch.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
git -C "$root/vendor/NewPipeExtractor" diff HEAD > "$root/extractor/patches/0001-teavm-compatibility.patch"
echo "Wrote extractor/patches/0001-teavm-compatibility.patch"
