#!/usr/bin/env bash
# Syncs the extractor and rebuilds ios/SourPipe/Resources/extractor.jsbundle. Needs JDK 21 (JAVA_HOME or
# PATH), or a JDK unpacked in .tools/.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${JAVA_HOME:-}" ] && ! command -v javac >/dev/null; then
    for jdk in "$root"/.tools/jdk*; do [ -d "$jdk" ] && export JAVA_HOME="$jdk"; done
fi
"$root/scripts/sync-extractor.sh"
cd "$root/extractor"
./gradlew --no-daemon --quiet bundle
cp "$root/extractor/upstream.lock" "$root/ios/SourPipe/Resources/extractor-version.txt"
ls -l "$root/ios/SourPipe/Resources/extractor.jsbundle"
